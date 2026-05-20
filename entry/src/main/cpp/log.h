#pragma once

#include <hilog/log.h>

#ifndef LOG_DOMAIN
#define LOG_DOMAIN 0xD002F00
#endif
#ifndef LOG_TAG
#define LOG_TAG "ovpnclient"
#endif

#define OVPN_LOGI(fmt, ...) ((void)OH_LOG_Print(LOG_APP, LOG_INFO,  LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__))
#define OVPN_LOGW(fmt, ...) ((void)OH_LOG_Print(LOG_APP, LOG_WARN,  LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__))
#define OVPN_LOGE(fmt, ...) ((void)OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__))
#define OVPN_LOGD(fmt, ...) ((void)OH_LOG_Print(LOG_APP, LOG_DEBUG, LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__))
