#pragma once

#include <napi/native_api.h>

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// openvpn3 public client API. Subclasses ClientAPI::OpenVPNClient, which in
// turn inherits TunBuilderBase — so tun_builder_* methods live on the same
// object as event/log/socket_protect callbacks.
#include <openvpn/client/ovpncli.hpp>

namespace ovpn {

// Single source of truth for the tun configuration as it is being built up by
// openvpn3 pushing settings to us through tun_builder_*. When establish() is
// called we serialise this struct over the threadsafe-function call to JS.
struct TunConfig {
    std::string sessionName;
    std::string remote;
    bool        remoteIpv6 = false;
    int         mtu = 1500;
    int         layer = 3;
    bool        rerouteIpv4 = false;
    bool        rerouteIpv6 = false;

    struct Address { std::string addr; int prefix; std::string gateway; bool ipv6; bool net30; };
    struct Route   { std::string addr; int prefix; int metric; bool ipv6; bool exclude; };
    struct Dns     { std::string addr; bool ipv6; };

    std::vector<Address>     addresses;
    std::vector<Route>       routes;
    std::vector<Dns>         dns;
    std::vector<std::string> searchDomains;

    void clear() { *this = TunConfig{}; }
};

class OvpnClient final : public openvpn::ClientAPI::OpenVPNClient {
public:
    explicit OvpnClient(napi_env env);
    ~OvpnClient() override;

    // ---- ArkTS-facing API (called from NAPI wrappers) ----

    void setTunHandler(napi_env env, napi_value cb);
    void setProtectHandler(napi_env env, napi_value cb);
    void setEventListener(napi_env env, napi_value cb);
    void setLogListener(napi_env env, napi_value cb);

    openvpn::ClientAPI::EvalConfig evalConfigSync(const std::string& configText,
                                                  const std::string& configFile);

    void provideCreds(const std::string& username,
                      const std::string& password,
                      bool cachePassword);

    // Sets the connect-time config (server override, proto override, etc).
    // Must be called before startConnect().
    void setConfig(openvpn::ClientAPI::Config cfg);

    void startConnect();      // launches worker thread; non-blocking
    void stop();              // requests teardown
    void pauseSession(const std::string& reason);
    void resumeSession();

    openvpn::ClientAPI::TransportStats transportStats();
    openvpn::ClientAPI::InterfaceStats interfaceStats();

    // Called from NAPI to fulfil a pending tun_builder_establish() request.
    // Pass fd < 0 to indicate failure (sets tunFd_ to -1, unblocks worker).
    void completeEstablish(int fd);
    // Called from NAPI to fulfil a pending socket_protect() request.
    void completeProtect(bool ok);

    // ---- openvpn3 callbacks (run on worker thread) ----

    void event(const openvpn::ClientAPI::Event& ev) override;
    void log(const openvpn::ClientAPI::LogInfo& ent) override;
    void external_pki_cert_request(openvpn::ClientAPI::ExternalPKICertRequest& req) override;
    void external_pki_sign_request(openvpn::ClientAPI::ExternalPKISignRequest& req) override;
    bool pause_on_connection_timeout() override { return false; }

    bool socket_protect(int socket, std::string remote, bool ipv6) override;

    // TunBuilderBase overrides
    bool tun_builder_new() override;
    bool tun_builder_set_layer(int layer) override;
    bool tun_builder_set_remote_address(const std::string& address, bool ipv6) override;
    bool tun_builder_add_address(const std::string& address, int prefix_length,
                                 const std::string& gateway, bool ipv6, bool net30) override;
    bool tun_builder_reroute_gw(bool ipv4, bool ipv6, unsigned int flags) override;
    bool tun_builder_add_route(const std::string& address, int prefix_length,
                               int metric, bool ipv6) override;
    bool tun_builder_exclude_route(const std::string& address, int prefix_length,
                                   int metric, bool ipv6) override;
    bool tun_builder_add_dns_server(const std::string& address, bool ipv6) override;
    bool tun_builder_add_search_domain(const std::string& domain) override;
    bool tun_builder_set_mtu(int mtu) override;
    bool tun_builder_set_session_name(const std::string& name) override;
    int  tun_builder_establish() override;
    void tun_builder_teardown(bool disconnect) override;
    bool tun_builder_persist() override { return true; }

private:
    void postEventToJs(const std::string& name, const std::string& info, int errorCode);
    void postLogToJs(std::string line);
    static void onTunReturned(napi_env env, napi_value /*js_cb*/, void* context, void* data);
    static void onProtectReturned(napi_env env, napi_value /*js_cb*/, void* context, void* data);
    static void onEventTrampoline(napi_env env, napi_value js_cb, void* context, void* data);
    static void onLogTrampoline(napi_env env, napi_value js_cb, void* context, void* data);

    napi_env env_;
    std::mutex cfgMutex_;
    openvpn::ClientAPI::Config config_;

    std::thread worker_;
    std::atomic<bool> running_{false};
    std::atomic<bool> stopRequested_{false};

    napi_threadsafe_function tsfTun_     = nullptr;
    napi_threadsafe_function tsfProtect_ = nullptr;
    napi_threadsafe_function tsfEvent_   = nullptr;
    napi_threadsafe_function tsfLog_     = nullptr;

    std::mutex tunMtx_;
    std::condition_variable tunCv_;
    bool tunDone_ = false;
    int  tunFd_ = -1;

    std::mutex protectMtx_;
    std::condition_variable protectCv_;
    bool protectDone_ = false;
    bool protectOk_   = false;

    TunConfig pendingTun_;
};

}  // namespace ovpn
