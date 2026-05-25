#include "ovpn_client.h"

#include "async_bridge.h"
#include "log.h"

#include <chrono>
#include <cstring>
#include <utility>

namespace ovpn {

// ---------- NAPI helpers (file-local) ----------

namespace {

napi_value asyncResourceName(napi_env env, const char* name) {
    napi_value v;
    napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &v);
    return v;
}

void setProp(napi_env env, napi_value obj, const char* key, napi_value v) {
    napi_set_named_property(env, obj, key, v);
}
void setProp(napi_env env, napi_value obj, const char* key, const std::string& s) {
    napi_value v;
    napi_create_string_utf8(env, s.c_str(), s.size(), &v);
    napi_set_named_property(env, obj, key, v);
}
void setProp(napi_env env, napi_value obj, const char* key, int n) {
    napi_value v;
    napi_create_int32(env, n, &v);
    napi_set_named_property(env, obj, key, v);
}
void setProp(napi_env env, napi_value obj, const char* key, bool b) {
    napi_value v;
    napi_get_boolean(env, b, &v);
    napi_set_named_property(env, obj, key, v);
}
void setProp(napi_env env, napi_value obj, const char* key, int64_t n) {
    napi_value v;
    napi_create_bigint_int64(env, n, &v);
    napi_set_named_property(env, obj, key, v);
}

napi_value tunConfigToJs(napi_env env, const TunConfig& cfg) {
    napi_value obj;
    napi_create_object(env, &obj);

    setProp(env, obj, "sessionName", cfg.sessionName);
    setProp(env, obj, "remoteAddress", cfg.remote);
    setProp(env, obj, "remoteIpv6", cfg.remoteIpv6);
    setProp(env, obj, "mtu", cfg.mtu);
    setProp(env, obj, "layer", cfg.layer);
    setProp(env, obj, "rerouteIpv4", cfg.rerouteIpv4);
    setProp(env, obj, "rerouteIpv6", cfg.rerouteIpv6);

    napi_value addrs;
    napi_create_array_with_length(env, cfg.addresses.size(), &addrs);
    for (size_t i = 0; i < cfg.addresses.size(); ++i) {
        napi_value a;
        napi_create_object(env, &a);
        setProp(env, a, "address", cfg.addresses[i].addr);
        setProp(env, a, "prefix", cfg.addresses[i].prefix);
        setProp(env, a, "gateway", cfg.addresses[i].gateway);
        setProp(env, a, "ipv6", cfg.addresses[i].ipv6);
        setProp(env, a, "net30", cfg.addresses[i].net30);
        napi_set_element(env, addrs, i, a);
    }
    setProp(env, obj, "addresses", addrs);

    napi_value routes;
    napi_create_array_with_length(env, cfg.routes.size(), &routes);
    for (size_t i = 0; i < cfg.routes.size(); ++i) {
        napi_value r;
        napi_create_object(env, &r);
        setProp(env, r, "address", cfg.routes[i].addr);
        setProp(env, r, "prefix", cfg.routes[i].prefix);
        setProp(env, r, "metric", cfg.routes[i].metric);
        setProp(env, r, "ipv6", cfg.routes[i].ipv6);
        setProp(env, r, "exclude", cfg.routes[i].exclude);
        napi_set_element(env, routes, i, r);
    }
    setProp(env, obj, "routes", routes);

    napi_value dns;
    napi_create_array_with_length(env, cfg.dns.size(), &dns);
    for (size_t i = 0; i < cfg.dns.size(); ++i) {
        napi_value d;
        napi_create_object(env, &d);
        setProp(env, d, "address", cfg.dns[i].addr);
        setProp(env, d, "ipv6", cfg.dns[i].ipv6);
        napi_set_element(env, dns, i, d);
    }
    setProp(env, obj, "dns", dns);

    napi_value domains;
    napi_create_array_with_length(env, cfg.searchDomains.size(), &domains);
    for (size_t i = 0; i < cfg.searchDomains.size(); ++i) {
        napi_value s;
        napi_create_string_utf8(env, cfg.searchDomains[i].c_str(),
                                cfg.searchDomains[i].size(), &s);
        napi_set_element(env, domains, i, s);
    }
    setProp(env, obj, "searchDomains", domains);

    return obj;
}

// Payload structs for fire-and-forget callbacks.
struct EventPayload {
    std::string name;
    std::string info;
    int         code = 0;
    bool        fatal = false;
    bool        error = false;
};

struct LogPayload { std::string line; };
struct ProtectPayload { int fd; std::string remote; bool ipv6; };

}  // namespace

// ---------- Construction ----------

OvpnClient::OvpnClient(napi_env env) : env_(env) {}

OvpnClient::~OvpnClient() {
    stopRequested_.store(true);
    if (running_.load()) {
        try { OpenVPNClient::stop(); } catch (...) {}
    }
    if (worker_.joinable()) {
        worker_.join();
    }
    auto release = [](napi_threadsafe_function& fn) {
        if (fn) {
            napi_release_threadsafe_function(fn, napi_tsfn_abort);
            fn = nullptr;
        }
    };
    release(tsfTun_);
    release(tsfProtect_);
    release(tsfEvent_);
    release(tsfLog_);
}

// ---------- Handler installation ----------

void OvpnClient::setTunHandler(napi_env env, napi_value cb) {
    if (tsfTun_) {
        napi_release_threadsafe_function(tsfTun_, napi_tsfn_release);
        tsfTun_ = nullptr;
    }
    napi_create_threadsafe_function(
        env, cb, nullptr,
        asyncResourceName(env, "ovpn.tunHandler"),
        0, 1, nullptr, nullptr, this,
        &OvpnClient::onTunReturned, &tsfTun_);
}

void OvpnClient::setProtectHandler(napi_env env, napi_value cb) {
    if (tsfProtect_) {
        napi_release_threadsafe_function(tsfProtect_, napi_tsfn_release);
        tsfProtect_ = nullptr;
    }
    napi_create_threadsafe_function(
        env, cb, nullptr,
        asyncResourceName(env, "ovpn.protectHandler"),
        0, 1, nullptr, nullptr, this,
        &OvpnClient::onProtectReturned, &tsfProtect_);
}

void OvpnClient::setEventListener(napi_env env, napi_value cb) {
    if (tsfEvent_) {
        napi_release_threadsafe_function(tsfEvent_, napi_tsfn_release);
        tsfEvent_ = nullptr;
    }
    napi_create_threadsafe_function(
        env, cb, nullptr,
        asyncResourceName(env, "ovpn.event"),
        0, 1, nullptr, nullptr, this,
        &OvpnClient::onEventTrampoline, &tsfEvent_);
}

void OvpnClient::setLogListener(napi_env env, napi_value cb) {
    if (tsfLog_) {
        napi_release_threadsafe_function(tsfLog_, napi_tsfn_release);
        tsfLog_ = nullptr;
    }
    napi_create_threadsafe_function(
        env, cb, nullptr,
        asyncResourceName(env, "ovpn.log"),
        0, 1, nullptr, nullptr, this,
        &OvpnClient::onLogTrampoline, &tsfLog_);
}

// ---------- Config / control ----------

openvpn::ClientAPI::EvalConfig OvpnClient::evalConfigSync(const std::string& content,
                                                          const std::string& file) {
    openvpn::ClientAPI::Config cfg;
    cfg.content = content;
    if (!file.empty()) {
        cfg.guiVersion = "openvpn-oh/0.1";
    }
    cfg.compressionMode = "yes";
    return eval_config(cfg);
}

void OvpnClient::provideCreds(const std::string& username,
                              const std::string& password,
                              bool /*cachePassword*/) {
    // openvpn3 release/3.10 dropped ProvideCreds.cachePassword. Caching is
    // now a Config-level concern (allowPasswordSave) or handled entirely
    // by the embedding app, which is what we do via CredentialStore.
    openvpn::ClientAPI::ProvideCreds creds;
    creds.username = username;
    creds.password = password;
    auto st = provide_creds(creds);
    if (st.error) {
        OVPN_LOGE("provide_creds error: %s", st.message.c_str());
    }
}

void OvpnClient::setConfig(openvpn::ClientAPI::Config cfg) {
    std::lock_guard<std::mutex> lock(cfgMutex_);
    config_ = std::move(cfg);
}

void OvpnClient::startConnect() {
    if (running_.exchange(true)) {
        OVPN_LOGW("startConnect called while already running");
        return;
    }
    stopRequested_.store(false);

    openvpn::ClientAPI::Config snapshot;
    {
        std::lock_guard<std::mutex> lock(cfgMutex_);
        snapshot = config_;
    }

    worker_ = std::thread([this, cfg = std::move(snapshot)]() mutable {
        try {
            auto evalRes = eval_config(cfg);
            if (evalRes.error) {
                postEventToJs("CONFIG_ERROR", evalRes.message, 1);
                running_.store(false);
                return;
            }
            auto status = connect();
            if (status.error) {
                postEventToJs("CONNECT_ERROR", status.message, 1);
            } else {
                postEventToJs("DISCONNECTED", status.message, 0);
            }
        } catch (const std::exception& e) {
            postEventToJs("FATAL", e.what(), 2);
        } catch (...) {
            postEventToJs("FATAL", "unknown C++ exception", 2);
        }
        running_.store(false);
    });
}

void OvpnClient::stop() {
    stopRequested_.store(true);
    try { OpenVPNClient::stop(); } catch (...) {}
}

void OvpnClient::pauseSession(const std::string& reason) {
    try { pause(reason); } catch (...) {}
}

void OvpnClient::resumeSession() {
    try { resume(); } catch (...) {}
}

openvpn::ClientAPI::TransportStats OvpnClient::transportStats() {
    return transport_stats();
}
openvpn::ClientAPI::InterfaceStats OvpnClient::interfaceStats() {
    return tun_stats();
}

void OvpnClient::completeEstablish(int fd) {
    {
        std::lock_guard<std::mutex> lock(tunMtx_);
        tunFd_ = fd;
        tunDone_ = true;
    }
    tunCv_.notify_all();
}

void OvpnClient::completeProtect(bool ok) {
    {
        std::lock_guard<std::mutex> lock(protectMtx_);
        protectOk_ = ok;
        protectDone_ = true;
    }
    protectCv_.notify_all();
}

// ---------- openvpn3 callbacks ----------

void OvpnClient::event(const openvpn::ClientAPI::Event& ev) {
    postEventToJs(ev.name, ev.info, ev.fatal ? 2 : (ev.error ? 1 : 0));
}

void OvpnClient::log(const openvpn::ClientAPI::LogInfo& ent) {
    postLogToJs(ent.text);
}

void OvpnClient::external_pki_cert_request(openvpn::ClientAPI::ExternalPKICertRequest& req) {
    req.error = true;
    req.errorText = "external PKI not implemented";
}

void OvpnClient::external_pki_sign_request(openvpn::ClientAPI::ExternalPKISignRequest& req) {
    req.error = true;
    req.errorText = "external PKI not implemented";
}

bool OvpnClient::socket_protect(int socket, std::string remote, bool ipv6) {
    if (!tsfProtect_) {
        OVPN_LOGW("socket_protect called with no handler installed; allowing");
        return true;
    }
    {
        std::lock_guard<std::mutex> lock(protectMtx_);
        protectDone_ = false;
        protectOk_   = false;
    }
    auto* payload = new ProtectPayload{ socket, std::move(remote), ipv6 };
    auto rc = napi_call_threadsafe_function(tsfProtect_, payload, napi_tsfn_blocking);
    if (rc != napi_ok) {
        delete payload;
        OVPN_LOGE("napi_call_threadsafe_function(protect) failed: %d", rc);
        return false;
    }
    std::unique_lock<std::mutex> lock(protectMtx_);
    if (!protectCv_.wait_for(lock, std::chrono::seconds(10), [&] { return protectDone_; })) {
        OVPN_LOGE("socket_protect timed out waiting for JS");
        return false;
    }
    return protectOk_;
}

// ---------- TunBuilder ----------

bool OvpnClient::tun_builder_new() {
    pendingTun_.clear();
    return true;
}
bool OvpnClient::tun_builder_set_layer(int layer) {
    pendingTun_.layer = layer;
    return true;
}
bool OvpnClient::tun_builder_set_remote_address(const std::string& address, bool ipv6) {
    pendingTun_.remote = address;
    pendingTun_.remoteIpv6 = ipv6;
    return true;
}
bool OvpnClient::tun_builder_add_address(const std::string& address, int prefix_length,
                                         const std::string& gateway, bool ipv6, bool net30) {
    pendingTun_.addresses.push_back({ address, prefix_length, gateway, ipv6, net30 });
    return true;
}
bool OvpnClient::tun_builder_reroute_gw(bool ipv4, bool ipv6, unsigned int /*flags*/) {
    pendingTun_.rerouteIpv4 = ipv4;
    pendingTun_.rerouteIpv6 = ipv6;
    return true;
}
bool OvpnClient::tun_builder_add_route(const std::string& address, int prefix_length,
                                       int metric, bool ipv6) {
    pendingTun_.routes.push_back({ address, prefix_length, metric, ipv6, /*exclude=*/false });
    return true;
}
bool OvpnClient::tun_builder_exclude_route(const std::string& address, int prefix_length,
                                           int metric, bool ipv6) {
    pendingTun_.routes.push_back({ address, prefix_length, metric, ipv6, /*exclude=*/true });
    return true;
}
bool OvpnClient::tun_builder_add_dns_server(const std::string& address, bool ipv6) {
    pendingTun_.dns.push_back({ address, ipv6 });
    return true;
}
bool OvpnClient::tun_builder_add_search_domain(const std::string& domain) {
    pendingTun_.searchDomains.push_back(domain);
    return true;
}
bool OvpnClient::tun_builder_set_mtu(int mtu) {
    pendingTun_.mtu = mtu;
    return true;
}
bool OvpnClient::tun_builder_set_session_name(const std::string& name) {
    pendingTun_.sessionName = name;
    return true;
}

int OvpnClient::tun_builder_establish() {
    if (!tsfTun_) {
        OVPN_LOGE("tun_builder_establish called but no tun handler installed");
        return -1;
    }
    {
        std::lock_guard<std::mutex> lock(tunMtx_);
        tunDone_ = false;
        tunFd_   = -1;
    }
    // pendingTun_ pointer is stable through the wait, we own it.
    auto rc = napi_call_threadsafe_function(tsfTun_, &pendingTun_, napi_tsfn_blocking);
    if (rc != napi_ok) {
        OVPN_LOGE("napi_call_threadsafe_function(tun) failed: %d", rc);
        return -1;
    }
    std::unique_lock<std::mutex> lock(tunMtx_);
    if (!tunCv_.wait_for(lock, std::chrono::seconds(30), [&] { return tunDone_; })) {
        OVPN_LOGE("tun_builder_establish timed out waiting for JS");
        return -1;
    }
    return tunFd_;
}

void OvpnClient::tun_builder_teardown(bool /*disconnect*/) {
    pendingTun_.clear();
}

// ---------- Fire-and-forget dispatchers ----------

void OvpnClient::postEventToJs(const std::string& name, const std::string& info, int code) {
    if (!tsfEvent_) return;
    auto* p = new EventPayload{ name, info, code, code >= 2, code >= 1 };
    if (napi_call_threadsafe_function(tsfEvent_, p, napi_tsfn_nonblocking) != napi_ok) {
        delete p;
    }
}

void OvpnClient::postLogToJs(std::string line) {
    if (!tsfLog_) return;
    auto* p = new LogPayload{ std::move(line) };
    if (napi_call_threadsafe_function(tsfLog_, p, napi_tsfn_nonblocking) != napi_ok) {
        delete p;
    }
}

// ---------- Trampolines (JS thread) ----------

void OvpnClient::onTunReturned(napi_env env, napi_value js_cb, void* context, void* data) {
    auto* self = static_cast<OvpnClient*>(context);
    auto* cfg  = static_cast<TunConfig*>(data);
    if (!env || !js_cb || !self || !cfg) return;
    napi_value undef;
    napi_get_undefined(env, &undef);
    napi_value cfgJs = tunConfigToJs(env, *cfg);
    napi_value result = nullptr;
    auto rc = napi_call_function(env, undef, js_cb, 1, &cfgJs, &result);
    if (rc != napi_ok) {
        OVPN_LOGE("tun handler call returned %d", rc);
        self->completeEstablish(-1);
    }
    // The JS handler is responsible for calling ovpn.completeEstablish(handle, fd).
}

void OvpnClient::onProtectReturned(napi_env env, napi_value js_cb, void* context, void* data) {
    auto* self = static_cast<OvpnClient*>(context);
    auto* p    = static_cast<ProtectPayload*>(data);
    if (!env || !js_cb || !self || !p) return;
    napi_value undef;
    napi_get_undefined(env, &undef);
    napi_value obj;
    napi_create_object(env, &obj);
    setProp(env, obj, "fd", p->fd);
    setProp(env, obj, "remote", p->remote);
    setProp(env, obj, "ipv6", p->ipv6);
    napi_value result = nullptr;
    auto rc = napi_call_function(env, undef, js_cb, 1, &obj, &result);
    delete p;
    if (rc != napi_ok) {
        OVPN_LOGE("protect handler call returned %d", rc);
        self->completeProtect(false);
    }
}

void OvpnClient::onEventTrampoline(napi_env env, napi_value js_cb, void* /*context*/, void* data) {
    auto* p = static_cast<EventPayload*>(data);
    if (!env || !js_cb || !p) { delete p; return; }
    napi_value undef;
    napi_get_undefined(env, &undef);
    napi_value obj;
    napi_create_object(env, &obj);
    setProp(env, obj, "name", p->name);
    setProp(env, obj, "info", p->info);
    setProp(env, obj, "code", p->code);
    setProp(env, obj, "fatal", p->fatal);
    setProp(env, obj, "error", p->error);
    napi_value result = nullptr;
    napi_call_function(env, undef, js_cb, 1, &obj, &result);
    delete p;
}

void OvpnClient::onLogTrampoline(napi_env env, napi_value js_cb, void* /*context*/, void* data) {
    auto* p = static_cast<LogPayload*>(data);
    if (!env || !js_cb || !p) { delete p; return; }
    napi_value undef;
    napi_get_undefined(env, &undef);
    napi_value s;
    napi_create_string_utf8(env, p->line.c_str(), p->line.size(), &s);
    napi_value result = nullptr;
    napi_call_function(env, undef, js_cb, 1, &s, &result);
    delete p;
}

}  // namespace ovpn
