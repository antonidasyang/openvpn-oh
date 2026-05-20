// SyncSlot<T> is fully inline in async_bridge.h. This translation unit exists
// only to keep CMakeLists.txt honest and to give the linker a place to anchor
// future helpers (e.g., external_pki sign / cert requests) that we will add
// when we move past username/password auth.

#include "async_bridge.h"

namespace ovpn {
}  // namespace ovpn
