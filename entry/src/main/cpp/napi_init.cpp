// NAPI module entry point for libovpnclient.
//
// All ArkTS calls into the engine come through this file. Each engine instance
// in ArkTS holds a 64-bit handle that resolves to a shared_ptr<OvpnClient> in
// the registry below. Handles are passed as JS bigint so we don't lose
// precision on 64-bit pointers (we use a counter, not the pointer itself).

#include "ovpn_client.h"
#include "log.h"

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

namespace ovpn {

// ---------- Registry ----------

namespace {

struct Registry {
    std::mutex mtx;
    std::unordered_map<uint64_t, std::shared_ptr<OvpnClient>> clients;
    uint64_t nextId = 1;
};

Registry& registry() {
    static Registry r;
    return r;
}

std::shared_ptr<OvpnClient> resolve(uint64_t handle) {
    std::lock_guard<std::mutex> lock(registry().mtx);
    auto it = registry().clients.find(handle);
    return it == registry().clients.end() ? nullptr : it->second;
}

// ---------- Helpers ----------

uint64_t readHandle(napi_env env, napi_value v) {
    bool lossless = false;
    uint64_t out = 0;
    napi_get_value_bigint_uint64(env, v, &out, &lossless);
    return out;
}

napi_value makeHandle(napi_env env, uint64_t h) {
    napi_value v;
    napi_create_bigint_uint64(env, h, &v);
    return v;
}

std::string readString(napi_env env, napi_value v) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, v, nullptr, 0, &len) != napi_ok) return {};
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, v, out.data(), len + 1, &len);
    return out;
}

int32_t readInt(napi_env env, napi_value v, int32_t fallback = 0) {
    int32_t out = fallback;
    napi_get_value_int32(env, v, &out);
    return out;
}

bool readBool(napi_env env, napi_value v, bool fallback = false) {
    bool out = fallback;
    napi_get_value_bool(env, v, &out);
    return out;
}

void setNamed(napi_env env, napi_value obj, const char* k, const std::string& s) {
    napi_value v;
    napi_create_string_utf8(env, s.c_str(), s.size(), &v);
    napi_set_named_property(env, obj, k, v);
}
void setNamed(napi_env env, napi_value obj, const char* k, bool b) {
    napi_value v;
    napi_get_boolean(env, b, &v);
    napi_set_named_property(env, obj, k, v);
}
void setNamed(napi_env env, napi_value obj, const char* k, int n) {
    napi_value v;
    napi_create_int32(env, n, &v);
    napi_set_named_property(env, obj, k, v);
}
void setNamedBig(napi_env env, napi_value obj, const char* k, int64_t n) {
    napi_value v;
    napi_create_bigint_int64(env, n, &v);
    napi_set_named_property(env, obj, k, v);
}

// Read N args from the callback info. Returns the actual count populated.
size_t getArgs(napi_env env, napi_callback_info info, napi_value* out, size_t max) {
    size_t argc = max;
    napi_get_cb_info(env, info, &argc, out, nullptr, nullptr);
    return argc;
}

}  // namespace

// ---------- NAPI methods ----------

static napi_value Create(napi_env env, napi_callback_info /*info*/) {
    auto client = std::make_shared<OvpnClient>(env);
    std::lock_guard<std::mutex> lock(registry().mtx);
    uint64_t id = registry().nextId++;
    registry().clients[id] = client;
    OVPN_LOGI("create() -> handle %llu", static_cast<unsigned long long>(id));
    return makeHandle(env, id);
}

static napi_value Destroy(napi_env env, napi_callback_info info) {
    napi_value args[1];
    if (getArgs(env, info, args, 1) < 1) return nullptr;
    uint64_t h = readHandle(env, args[0]);
    std::shared_ptr<OvpnClient> drained;
    {
        std::lock_guard<std::mutex> lock(registry().mtx);
        auto it = registry().clients.find(h);
        if (it != registry().clients.end()) {
            drained = std::move(it->second);
            registry().clients.erase(it);
        }
    }
    // drained's destructor stops the worker and releases the threadsafe fns.
    return nullptr;
}

static napi_value EvalConfig(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    std::string content = readString(env, args[1]);
    auto res = client->evalConfigSync(content, "");
    napi_value obj;
    napi_create_object(env, &obj);
    setNamed(env, obj, "error",          res.error);
    setNamed(env, obj, "message",        res.message);
    setNamed(env, obj, "profileName",    res.profileName);
    setNamed(env, obj, "userlockedUsername", res.userlockedUsername);
    setNamed(env, obj, "remoteHost",     res.remoteHost);
    setNamed(env, obj, "remotePort",     res.remotePort);
    setNamed(env, obj, "remoteProto",    res.remoteProto);
    setNamed(env, obj, "autologin",      res.autologin);
    setNamed(env, obj, "externalPki",    res.externalPki);
    setNamed(env, obj, "staticChallenge", res.staticChallenge);
    setNamed(env, obj, "staticChallengeEcho", res.staticChallengeEcho);
    setNamed(env, obj, "privateKeyPasswordRequired", res.privateKeyPasswordRequired);
    setNamed(env, obj, "allowPasswordSave", res.allowPasswordSave);
    return obj;
}

static napi_value SetConfig(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    openvpn::ClientAPI::Config cfg;
    napi_value v;
    auto pick = [&](const char* k) -> napi_value {
        napi_value out;
        if (napi_get_named_property(env, args[1], k, &out) != napi_ok) return nullptr;
        napi_valuetype t;
        napi_typeof(env, out, &t);
        return (t == napi_undefined || t == napi_null) ? nullptr : out;
    };
    if ((v = pick("content")))         cfg.content = readString(env, v);
    if ((v = pick("guiVersion")))      cfg.guiVersion = readString(env, v);
    if ((v = pick("serverOverride")))  cfg.serverOverride = readString(env, v);
    if ((v = pick("portOverride")))    cfg.portOverride = readString(env, v);
    if ((v = pick("protoOverride")))   cfg.protoOverride = readString(env, v);
    // Note: openvpn3 release/3.10 dropped the Config.ipv6 string field.
    // IPv6 behaviour is now controlled at the OS / tun-builder level.
    if ((v = pick("compressionMode"))) cfg.compressionMode = readString(env, v);
    if ((v = pick("tlsCertProfileOverride")))
                                       cfg.tlsCertProfileOverride = readString(env, v);
    if ((v = pick("disableClientCert"))) cfg.disableClientCert = readBool(env, v);
    if ((v = pick("connTimeout")))     cfg.connTimeout = readInt(env, v);
    if ((v = pick("tunPersist")))      cfg.tunPersist = readBool(env, v);
    if ((v = pick("googleDnsFallback"))) cfg.googleDnsFallback = readBool(env, v);
    if ((v = pick("autologinSessions"))) cfg.autologinSessions = readBool(env, v);
    if ((v = pick("info")))            cfg.info = readBool(env, v);
    client->setConfig(std::move(cfg));
    return nullptr;
}

static napi_value SetTunHandler(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->setTunHandler(env, args[1]);
    return nullptr;
}

static napi_value SetProtectHandler(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->setProtectHandler(env, args[1]);
    return nullptr;
}

static napi_value SetEventListener(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->setEventListener(env, args[1]);
    return nullptr;
}

static napi_value SetLogListener(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->setLogListener(env, args[1]);
    return nullptr;
}

static napi_value ProvideCreds(napi_env env, napi_callback_info info) {
    napi_value args[4];
    if (getArgs(env, info, args, 4) < 4) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->provideCreds(readString(env, args[1]),
                         readString(env, args[2]),
                         readBool(env, args[3]));
    return nullptr;
}

static napi_value StartConnect(napi_env env, napi_callback_info info) {
    napi_value args[1];
    if (getArgs(env, info, args, 1) < 1) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->startConnect();
    return nullptr;
}

static napi_value StopConnect(napi_env env, napi_callback_info info) {
    napi_value args[1];
    if (getArgs(env, info, args, 1) < 1) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->stop();
    return nullptr;
}

static napi_value PauseSession(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->pauseSession(readString(env, args[1]));
    return nullptr;
}

static napi_value ResumeSession(napi_env env, napi_callback_info info) {
    napi_value args[1];
    if (getArgs(env, info, args, 1) < 1) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->resumeSession();
    return nullptr;
}

static napi_value CompleteEstablish(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->completeEstablish(readInt(env, args[1], -1));
    return nullptr;
}

static napi_value CompleteProtect(napi_env env, napi_callback_info info) {
    napi_value args[2];
    if (getArgs(env, info, args, 2) < 2) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;
    client->completeProtect(readBool(env, args[1], false));
    return nullptr;
}

static napi_value GetStats(napi_env env, napi_callback_info info) {
    napi_value args[1];
    if (getArgs(env, info, args, 1) < 1) return nullptr;
    auto client = resolve(readHandle(env, args[0]));
    if (!client) return nullptr;

    auto t = client->transportStats();
    auto i = client->interfaceStats();

    napi_value obj, tr, in;
    napi_create_object(env, &obj);
    napi_create_object(env, &tr);
    napi_create_object(env, &in);

    setNamedBig(env, tr, "bytesIn",   static_cast<int64_t>(t.bytesIn));
    setNamedBig(env, tr, "bytesOut",  static_cast<int64_t>(t.bytesOut));
    setNamed   (env, tr, "lastPacketReceived", static_cast<int>(t.lastPacketReceived));

    setNamedBig(env, in, "bytesIn",   static_cast<int64_t>(i.bytesIn));
    setNamedBig(env, in, "bytesOut",  static_cast<int64_t>(i.bytesOut));
    setNamedBig(env, in, "packetsIn", static_cast<int64_t>(i.packetsIn));
    setNamedBig(env, in, "packetsOut",static_cast<int64_t>(i.packetsOut));
    setNamedBig(env, in, "errorsIn",  static_cast<int64_t>(i.errorsIn));
    setNamedBig(env, in, "errorsOut", static_cast<int64_t>(i.errorsOut));

    napi_set_named_property(env, obj, "transport", tr);
    napi_set_named_property(env, obj, "tun",       in);
    return obj;
}

// ---------- Module init ----------

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "create",             nullptr, Create,             nullptr, nullptr, nullptr, napi_default, nullptr },
        { "destroy",            nullptr, Destroy,            nullptr, nullptr, nullptr, napi_default, nullptr },
        { "evalConfig",         nullptr, EvalConfig,         nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setConfig",          nullptr, SetConfig,          nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setTunHandler",      nullptr, SetTunHandler,      nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setProtectHandler",  nullptr, SetProtectHandler,  nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setEventListener",   nullptr, SetEventListener,   nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setLogListener",     nullptr, SetLogListener,     nullptr, nullptr, nullptr, napi_default, nullptr },
        { "provideCreds",       nullptr, ProvideCreds,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startConnect",       nullptr, StartConnect,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stop",               nullptr, StopConnect,        nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pause",              nullptr, PauseSession,       nullptr, nullptr, nullptr, napi_default, nullptr },
        { "resume",             nullptr, ResumeSession,      nullptr, nullptr, nullptr, napi_default, nullptr },
        { "completeEstablish",  nullptr, CompleteEstablish,  nullptr, nullptr, nullptr, napi_default, nullptr },
        { "completeProtect",    nullptr, CompleteProtect,    nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getStats",           nullptr, GetStats,           nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

}  // namespace ovpn

static napi_module ovpnclient_module = {
    .nm_version     = 1,
    .nm_flags       = 0,
    .nm_filename    = nullptr,
    .nm_register_func = ovpn::Init,
    .nm_modname     = "ovpnclient",
    .nm_priv        = nullptr,
    .reserved       = { nullptr, nullptr, nullptr, nullptr },
};

extern "C" __attribute__((constructor)) void RegisterOvpnClient() {
    napi_module_register(&ovpnclient_module);
}
