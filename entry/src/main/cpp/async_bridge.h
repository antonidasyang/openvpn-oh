#pragma once

#include <napi/native_api.h>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <string>

namespace ovpn {

// Owns a napi_threadsafe_function and provides a typed, blocking helper
// `requestSync<T>(...)` for the C++ worker thread to pose a question to the
// ArkTS main thread and wait for its answer. The ArkTS side completes the
// request by calling back into a NAPI method that finds the SyncSlot and
// fulfils it.
//
// Used for:
//   - tun_builder_establish() -> setUp(VpnConfig)         (returns fd)
//   - socket_protect()        -> VpnConnection.protect()  (returns bool)
//   - external_pki_*          (future)
template <typename T>
class SyncSlot {
public:
    bool wait(int timeout_ms = 30000) {
        std::unique_lock<std::mutex> lock(mtx_);
        if (done_) return true;
        return cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                            [&] { return done_; });
    }
    void set(T value) {
        std::lock_guard<std::mutex> lock(mtx_);
        value_ = std::move(value);
        done_ = true;
        cv_.notify_all();
    }
    bool done() const {
        std::lock_guard<std::mutex> lock(mtx_);
        return done_;
    }
    const T& value() const { return *value_; }
    T take() { return std::move(*value_); }

private:
    mutable std::mutex mtx_;
    std::condition_variable cv_;
    bool done_ = false;
    std::optional<T> value_;
};

}  // namespace ovpn
