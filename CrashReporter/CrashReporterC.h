#ifndef CrashReporterC_h
#define CrashReporterC_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void CrashReporter_Initialize(const char* apiEndpoint);
bool CrashReporter_IsInitialized(void);
int32_t CrashReporter_GetPendingCrashCount(void);
void CrashReporter_SendPendingCrashes(void);
void CrashReporter_SetUserContext(const char* userId, const char* email, const char* username);
void CrashReporter_SetTag(const char* key, const char* value);
void CrashReporter_RemoveTag(const char* key);
void CrashReporter_SetEnvironment(const char* env);
void CrashReporter_AddBreadcrumb(const char* category, const char* message, const char* level);

#ifdef __cplusplus
}
#endif

#endif
