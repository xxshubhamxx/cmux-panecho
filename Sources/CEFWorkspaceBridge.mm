#import "CEFWorkspaceBridge.h"
#import "CEFShim.h"

#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>
#import <atomic>
#import <climits>
#import <cmath>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef int (*CMUXCEFExecuteProcessFn)(const cef_main_args_t *args, void *application, void *windowsSandboxInfo);
typedef int (*CMUXCEFInitializeFn)(const cef_main_args_t *args, const cef_settings_t *settings, void *application, void *windowsSandboxInfo);
typedef const char *(*CMUXCEFApiHashFn)(int version, int entry);
typedef int (*CMUXCEFGetExitCodeFn)(void);
typedef void (*CMUXCEFDoMessageLoopWorkFn)(void);
typedef void (*CMUXCEFShutdownFn)(void);

static void CMUXCEFFreeUTF16String(char16_t *str) {
    if (str != nullptr) {
        free(str);
    }
}

static cef_string_t CMUXCEFStringFromNSString(NSString *value) {
    cef_string_t result = {};
    if (value.length == 0) {
        return result;
    }

    NSUInteger length = value.length;
    char16_t *buffer = static_cast<char16_t *>(calloc(length + 1, sizeof(char16_t)));
    if (buffer == nullptr) {
        return result;
    }

    [value getCharacters:reinterpret_cast<unichar *>(buffer) range:NSMakeRange(0, length)];
    buffer[length] = 0;
    result.str = buffer;
    result.length = length;
    result.dtor = &CMUXCEFFreeUTF16String;
    return result;
}

static void CMUXCEFClearString(cef_string_t *value) {
    if (value == nullptr) {
        return;
    }
    if (value->dtor != nullptr && value->str != nullptr) {
        value->dtor(value->str);
    }
    value->str = nullptr;
    value->length = 0;
    value->dtor = nullptr;
}

static NSString *CMUXCEFStringToNSString(const cef_string_t *value) {
    if (value == nullptr || value->str == nullptr || value->length == 0) {
        return @"";
    }
    return [[NSString alloc] initWithCharacters:reinterpret_cast<const unichar *>(value->str)
                                         length:value->length];
}

static NSString *CMUXCEFJSONLiteral(NSString *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[value ?: @""] options:0 error:nil];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length < 2) {
        return @"\"\"";
    }
    return [text substringWithRange:NSMakeRange(1, text.length - 2)];
}

static const int64_t CMUXCEFWindowsToUnixEpochDeltaSeconds = 11644473600LL;
static const int64_t CMUXCEFMicrosecondsPerSecond = 1000000LL;
static const int64_t CMUXCEFMessagePumpFallbackDelayMS = 1000 / 60;
static const int64_t CMUXCEFMessagePumpMaxDelayMS = 1000 / 30;
static const int CMUXCEFAPIVersionExperimental = 999999;

static cef_basetime_t CMUXCEFBaseTimeFromUnixTimeInterval(NSTimeInterval unixTime) {
    cef_basetime_t value = {};
    value.val = (int64_t)((unixTime + (NSTimeInterval)CMUXCEFWindowsToUnixEpochDeltaSeconds) * (NSTimeInterval)CMUXCEFMicrosecondsPerSecond);
    return value;
}

static NSNumber *CMUXCEFUnixTimestampNumber(const cef_basetime_t &value) {
    if (value.val == 0) {
        return nil;
    }
    double unixTime = ((double)value.val / (double)CMUXCEFMicrosecondsPerSecond) - (double)CMUXCEFWindowsToUnixEpochDeltaSeconds;
    return @((NSInteger)unixTime);
}

static NSDictionary *CMUXCEFDictionaryFromCookie(const cef_cookie_t *cookie) {
    if (cookie == nullptr) {
        return @{};
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"name"] = CMUXCEFStringToNSString(&cookie->name);
    out[@"value"] = CMUXCEFStringToNSString(&cookie->value);
    out[@"domain"] = CMUXCEFStringToNSString(&cookie->domain);
    out[@"path"] = CMUXCEFStringToNSString(&cookie->path);
    out[@"secure"] = @(cookie->secure != 0);
    out[@"session_only"] = @(cookie->has_expires == 0);
    if (cookie->has_expires) {
        out[@"expires"] = CMUXCEFUnixTimestampNumber(cookie->expires) ?: NSNull.null;
    } else {
        out[@"expires"] = NSNull.null;
    }
    return out;
}

static NSString *CMUXCEFURLStringForCookieDictionary(NSDictionary *raw, NSString *fallbackURLString) {
    NSString *urlString = [raw[@"url"] isKindOfClass:[NSString class]] ? raw[@"url"] : nil;
    if (urlString.length > 0) {
        return urlString;
    }
    if (fallbackURLString.length > 0) {
        return fallbackURLString;
    }
    NSString *domain = [raw[@"domain"] isKindOfClass:[NSString class]] ? raw[@"domain"] : nil;
    if (domain.length == 0) {
        return nil;
    }
    NSString *path = [raw[@"path"] isKindOfClass:[NSString class]] ? raw[@"path"] : @"/";
    if (path.length == 0) {
        path = @"/";
    }
    BOOL secure = [raw[@"secure"] respondsToSelector:@selector(boolValue)] ? [raw[@"secure"] boolValue] : NO;
    NSString *scheme = secure ? @"https" : @"http";
    NSString *host = [domain hasPrefix:@"."] ? [domain substringFromIndex:1] : domain;
    if (host.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"%@://%@%@", scheme, host, [path hasPrefix:@"/"] ? path : [@"/" stringByAppendingString:path]];
}

static BOOL CMUXCEFPopulateCookie(cef_cookie_t *target, NSDictionary *raw, NSString *fallbackURLString) {
    if (target == nullptr) {
        return NO;
    }
    NSString *name = [raw[@"name"] isKindOfClass:[NSString class]] ? raw[@"name"] : nil;
    NSString *value = [raw[@"value"] isKindOfClass:[NSString class]] ? raw[@"value"] : nil;
    NSString *urlString = CMUXCEFURLStringForCookieDictionary(raw, fallbackURLString);
    if (name.length == 0 || value == nil || urlString.length == 0) {
        return NO;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    NSString *host = components.host ?: @"";
    if (host.length == 0) {
        return NO;
    }

    NSString *domain = [raw[@"domain"] isKindOfClass:[NSString class]] ? raw[@"domain"] : host;
    NSString *path = [raw[@"path"] isKindOfClass:[NSString class]] ? raw[@"path"] : @"/";
    if (path.length == 0) {
        path = @"/";
    }

    target->size = sizeof(cef_cookie_t);
    target->name = CMUXCEFStringFromNSString(name);
    target->value = CMUXCEFStringFromNSString(value);
    target->domain = CMUXCEFStringFromNSString(domain);
    target->path = CMUXCEFStringFromNSString(path);
    target->secure = [raw[@"secure"] respondsToSelector:@selector(boolValue)] ? ([raw[@"secure"] boolValue] ? 1 : 0) : 0;
    target->httponly = [raw[@"http_only"] respondsToSelector:@selector(boolValue)] ? ([raw[@"http_only"] boolValue] ? 1 : 0) : 0;
    target->same_site = CEF_COOKIE_SAME_SITE_UNSPECIFIED;
    target->priority = CEF_COOKIE_PRIORITY_MEDIUM;

    id expiresValue = raw[@"expires"];
    NSNumber *expiresNumber = nil;
    if ([expiresValue isKindOfClass:[NSNumber class]]) {
        expiresNumber = expiresValue;
    }
    if (expiresNumber != nil) {
        target->has_expires = 1;
        target->expires = CMUXCEFBaseTimeFromUnixTimeInterval(expiresNumber.doubleValue);
    }
    return YES;
}

static void CMUXCEFClearCookie(cef_cookie_t *cookie) {
    if (cookie == nullptr) {
        return;
    }
    CMUXCEFClearString(&cookie->name);
    CMUXCEFClearString(&cookie->value);
    CMUXCEFClearString(&cookie->domain);
    CMUXCEFClearString(&cookie->path);
}

static cef_main_args_t CMUXCEFMainArgsFromProcessArguments(void) {
    NSArray<NSString *> *processArguments = NSProcessInfo.processInfo.arguments;
    BOOL hasMockKeychainSwitch = NO;
    BOOL hasDisableGPUSwitch = NO;
    BOOL hasDisableGPUCompositingSwitch = NO;
    for (NSString *argument in processArguments) {
        if ([argument isEqualToString:@"--use-mock-keychain"]) {
            hasMockKeychainSwitch = YES;
        } else if ([argument isEqualToString:@"--disable-gpu"]) {
            hasDisableGPUSwitch = YES;
        } else if ([argument isEqualToString:@"--disable-gpu-compositing"]) {
            hasDisableGPUCompositingSwitch = YES;
        }
    }

    NSMutableArray<NSString *> *arguments = [processArguments mutableCopy];
    if (!hasMockKeychainSwitch) {
        [arguments addObject:@"--use-mock-keychain"];
    }
    if (!hasDisableGPUSwitch) {
        [arguments addObject:@"--disable-gpu"];
    }
    if (!hasDisableGPUCompositingSwitch) {
        [arguments addObject:@"--disable-gpu-compositing"];
    }

    cef_main_args_t result = {};
    result.argc = (int)arguments.count;
    if (arguments.count == 0) {
        return result;
    }

    result.argv = static_cast<char **>(calloc(arguments.count, sizeof(char *)));
    if (result.argv == nullptr) {
        result.argc = 0;
        return result;
    }

    for (NSUInteger index = 0; index < arguments.count; index++) {
        result.argv[index] = strdup(arguments[index].UTF8String ?: "");
    }
    return result;
}

static void CMUXCEFFreeMainArgs(cef_main_args_t *args) {
    if (args == nullptr || args->argv == nullptr) {
        return;
    }
    for (int index = 0; index < args->argc; index++) {
        free(args->argv[index]);
    }
    free(args->argv);
    args->argv = nullptr;
    args->argc = 0;
}

static NSString *CMUXCEFHelperExecutablePath(NSString *helperAppPath) {
    if (helperAppPath.length == 0) {
        return nil;
    }
    NSBundle *helperBundle = [NSBundle bundleWithPath:helperAppPath];
    NSString *executableName = [helperBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    if (executableName.length == 0) {
        executableName = helperAppPath.stringByDeletingPathExtension.lastPathComponent;
    }
    return [[[helperAppPath stringByAppendingPathComponent:@"Contents"]
        stringByAppendingPathComponent:@"MacOS"]
        stringByAppendingPathComponent:executableName];
}

static BOOL CMUXCEFPathEqualsStandardized(NSString *lhs, NSString *rhs) {
    if (lhs.length == 0 || rhs.length == 0) {
        return NO;
    }
    return [lhs.stringByStandardizingPath isEqualToString:rhs.stringByStandardizingPath];
}

static BOOL CMUXCEFPathHasStandardizedPrefix(NSString *path, NSString *prefix) {
    if (path.length == 0 || prefix.length == 0) {
        return NO;
    }
    NSString *standardizedPath = path.stringByStandardizingPath;
    NSString *standardizedPrefix = prefix.stringByStandardizingPath;
    return [standardizedPath isEqualToString:standardizedPrefix]
        || [standardizedPath hasPrefix:[standardizedPrefix stringByAppendingString:@"/"]];
}

static void CMUXCEFReleaseRefCounted(cef_base_ref_counted_t *base) {
    if (base != nullptr && base->release != nullptr) {
        base->release(base);
    }
}

@class CEFWorkspaceBridge;
@class CEFCookieVisitWaiter;
@class CEFCookieWriteWaiter;
@class CEFGlobalRuntimeManager;

static void CMUXCEFDebugLog(NSString *message);

struct CMUXCEFCookieVisitorState {
    cef_cookie_visitor_t visitor;
    std::atomic_int refCount;
    CEFCookieVisitWaiter *__strong waiter;
    NSString *__strong nameFilter;
    NSString *__strong domainFilter;
    BOOL deleteMatches;
};

struct CMUXCEFSetCookieCallbackState {
    cef_set_cookie_callback_t callback;
    std::atomic_int refCount;
    CEFCookieWriteWaiter *__strong waiter;
};

struct CMUXCEFBrowserProcessHandlerState {
    cef_browser_process_handler_t handler;
    std::atomic_int refCount;
    __unsafe_unretained CEFGlobalRuntimeManager *manager;
};

struct CMUXCEFAppState {
    cef_app_t app;
    std::atomic_int refCount;
    CMUXCEFBrowserProcessHandlerState *browserProcessHandler;
};

static CMUXCEFBrowserProcessHandlerState *CMUXCEFBrowserProcessHandlerFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFBrowserProcessHandlerState *>(
        reinterpret_cast<char *>(base) - offsetof(CMUXCEFBrowserProcessHandlerState, handler.base)
    );
}

static CMUXCEFAppState *CMUXCEFAppFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFAppState *>(
        reinterpret_cast<char *>(base) - offsetof(CMUXCEFAppState, app.base)
    );
}

static void CMUXCEFBrowserProcessHandlerAddRef(cef_base_ref_counted_t *base) {
    CMUXCEFBrowserProcessHandlerFromBase(base)->refCount.fetch_add(1);
}

static int CMUXCEFBrowserProcessHandlerRelease(cef_base_ref_counted_t *base) {
    CMUXCEFBrowserProcessHandlerState *state = CMUXCEFBrowserProcessHandlerFromBase(base);
    if (state->refCount.fetch_sub(1) == 1) {
        delete state;
        return 1;
    }
    return 0;
}

static int CMUXCEFBrowserProcessHandlerHasOneRef(cef_base_ref_counted_t *base) {
    return CMUXCEFBrowserProcessHandlerFromBase(base)->refCount.load() == 1;
}

static int CMUXCEFBrowserProcessHandlerHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return CMUXCEFBrowserProcessHandlerFromBase(base)->refCount.load() >= 1;
}

static void CMUXCEFAppAddRef(cef_base_ref_counted_t *base) {
    CMUXCEFAppFromBase(base)->refCount.fetch_add(1);
}

static int CMUXCEFAppRelease(cef_base_ref_counted_t *base) {
    CMUXCEFAppState *state = CMUXCEFAppFromBase(base);
    if (state->refCount.fetch_sub(1) == 1) {
        if (state->browserProcessHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&state->browserProcessHandler->handler.base);
            state->browserProcessHandler = nullptr;
        }
        delete state;
        return 1;
    }
    return 0;
}

static int CMUXCEFAppHasOneRef(cef_base_ref_counted_t *base) {
    return CMUXCEFAppFromBase(base)->refCount.load() == 1;
}

static int CMUXCEFAppHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return CMUXCEFAppFromBase(base)->refCount.load() >= 1;
}

@interface CEFBrowserContainerView : NSView <CMUXBrowserSurfaceFocusControlling>
@property(nonatomic, weak) CEFWorkspaceBridge *bridge;
@property(nonatomic, weak) NSView *activeDragDestinationView;
@property(nonatomic) BOOL cmuxAllowsFirstResponderAcquisition;
@property(nonatomic, readonly) BOOL cmuxAllowsFirstResponderAcquisitionEffective;
@property(nonatomic, readonly) NSInteger cmuxDebugPointerFocusAllowanceDepth;
@end

@interface CEFGlobalRuntimeManager : NSObject
@property(nonatomic, readonly) BOOL hasRequiredSymbols;
@property(nonatomic, readonly) BOOL isStarted;
@property(nonatomic, readonly, copy) NSString *runtimeStatusSummary;
@property(nonatomic, readonly) CMUXCEFStringUserfreeFreeFn stringUserfreeFreeFn;
@property(nonatomic, readonly) CMUXCEFStringListAllocFn stringListAllocFn;
@property(nonatomic, readonly) CMUXCEFStringListSizeFn stringListSizeFn;
@property(nonatomic, readonly) CMUXCEFStringListValueFn stringListValueFn;
@property(nonatomic, readonly) CMUXCEFStringListAppendFn stringListAppendFn;
@property(nonatomic, readonly) CMUXCEFStringListFreeFn stringListFreeFn;
@property(nonatomic, readonly) CMUXCEFRequestContextCreateContextFn requestContextCreateContextFn;
@property(nonatomic, readonly) CMUXCEFValueCreateFn valueCreateFn;
@property(nonatomic, readonly) CMUXCEFDictionaryValueCreateFn dictionaryValueCreateFn;
@property(nonatomic, readonly) CMUXCEFBrowserCreateBrowserSyncFn browserCreateBrowserSyncFn;
+ (instancetype)sharedManager;
- (BOOL)ensureStartedWithFrameworkPath:(NSString *)frameworkPath
                         helperAppPath:(nullable NSString *)helperAppPath
                        mainBundlePath:(NSString *)mainBundlePath
                  runtimeCacheRootPath:(NSString *)runtimeCacheRootPath
                      errorDescription:(NSString * _Nullable * _Nullable)errorDescription;
- (void)requestMessagePumpWorkDelayMS:(int64_t)delayMS;
@end

@interface CEFGlobalRuntimeManager ()
@property(nonatomic) BOOL hasRequiredSymbols;
@property(nonatomic) BOOL didAttemptStart;
@property(nonatomic) BOOL isStarted;
@property(nonatomic, copy) NSString *runtimeStatusSummary;
@property(nonatomic) CMUXCEFApiHashFn apiHashFn;
@property(nonatomic) CMUXCEFExecuteProcessFn executeProcessFn;
@property(nonatomic) CMUXCEFInitializeFn initializeFn;
@property(nonatomic) CMUXCEFGetExitCodeFn getExitCodeFn;
@property(nonatomic) CMUXCEFDoMessageLoopWorkFn doMessageLoopWorkFn;
@property(nonatomic) CMUXCEFShutdownFn shutdownFn;
@property(nonatomic) CMUXCEFStringUserfreeFreeFn stringUserfreeFreeFn;
@property(nonatomic) CMUXCEFStringListAllocFn stringListAllocFn;
@property(nonatomic) CMUXCEFStringListSizeFn stringListSizeFn;
@property(nonatomic) CMUXCEFStringListValueFn stringListValueFn;
@property(nonatomic) CMUXCEFStringListAppendFn stringListAppendFn;
@property(nonatomic) CMUXCEFStringListFreeFn stringListFreeFn;
@property(nonatomic) CMUXCEFRequestContextCreateContextFn requestContextCreateContextFn;
@property(nonatomic) CMUXCEFValueCreateFn valueCreateFn;
@property(nonatomic) CMUXCEFDictionaryValueCreateFn dictionaryValueCreateFn;
@property(nonatomic) CMUXCEFBrowserCreateBrowserSyncFn browserCreateBrowserSyncFn;
@property(nonatomic) CMUXCEFAppState *appState;
@property(nonatomic, strong) NSTimer *messagePumpTimer;
@property(nonatomic, strong) id terminateObserver;
@property(nonatomic) BOOL isPerformingMessageLoopWork;
@property(nonatomic) BOOL messageLoopWorkReentrancyDetected;
@property(nonatomic) BOOL hasPendingImmediateMessagePumpWork;
@end

@interface CEFAutomationWaiter : NSObject
@property(nonatomic, readonly) dispatch_semaphore_t semaphore;
@property(nonatomic, strong, nullable) id resultValue;
@property(nonatomic, copy, nullable) NSString *errorDescription;
@property(nonatomic) BOOL completed;
@end

@interface CEFCookieVisitWaiter : NSObject
@property(nonatomic, readonly) dispatch_semaphore_t semaphore;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *cookies;
@property(nonatomic, copy, nullable) NSString *errorDescription;
@property(nonatomic) BOOL completed;
@property(nonatomic) BOOL sawCookie;
@property(nonatomic, strong) NSDate *lastUpdateAt;
@end

@interface CEFCookieWriteWaiter : NSObject
@property(nonatomic, readonly) dispatch_semaphore_t semaphore;
@property(nonatomic, copy, nullable) NSString *errorDescription;
@property(nonatomic) BOOL completed;
@property(nonatomic) NSInteger integerResult;
@end

static void CMUXCEFBrowserProcessHandlerOnScheduleMessagePumpWork(
    cef_browser_process_handler_t *self,
    int64_t delay_ms
) {
    CMUXCEFBrowserProcessHandlerState *state = reinterpret_cast<CMUXCEFBrowserProcessHandlerState *>(
        reinterpret_cast<char *>(self) - offsetof(CMUXCEFBrowserProcessHandlerState, handler)
    );
    [state->manager requestMessagePumpWorkDelayMS:delay_ms];
}

static void CMUXCEFBrowserProcessHandlerOnContextInitialized(
    cef_browser_process_handler_t *self
) {
    CMUXCEFBrowserProcessHandlerState *state = reinterpret_cast<CMUXCEFBrowserProcessHandlerState *>(
        reinterpret_cast<char *>(self) - offsetof(CMUXCEFBrowserProcessHandlerState, handler)
    );
    if (state->manager != nil) {
        state->manager.runtimeStatusSummary = @"CEF context initialized";
    }
    CMUXCEFDebugLog(@"browserProcessHandler on_context_initialized");
}

static void CMUXCEFBrowserProcessHandlerOnBeforeChildProcessLaunch(
    __unused cef_browser_process_handler_t *self,
    __unused void *command_line
) {
    CMUXCEFDebugLog(@"browserProcessHandler on_before_child_process_launch");
}

static int CMUXCEFBrowserProcessHandlerOnAlreadyRunningAppRelaunch(
    __unused cef_browser_process_handler_t *self,
    __unused void *command_line,
    __unused const cef_string_t *current_directory
) {
    CMUXCEFDebugLog(@"browserProcessHandler on_already_running_app_relaunch");
    return 0;
}

static void CMUXCEFAppOnBeforeCommandLineProcessing(
    cef_app_t *self,
    const cef_string_t *process_type,
    __unused void *command_line
) {
    NSString *processType = CMUXCEFStringToNSString(process_type);
    CMUXCEFDebugLog([NSString stringWithFormat:@"app on_before_command_line_processing processType=%@",
                     processType.length > 0 ? processType : @"<browser>"]);
}

static cef_browser_process_handler_t *CMUXCEFAppGetBrowserProcessHandler(cef_app_t *self) {
    CMUXCEFAppState *state = reinterpret_cast<CMUXCEFAppState *>(
        reinterpret_cast<char *>(self) - offsetof(CMUXCEFAppState, app)
    );
#if DEBUG
    fprintf(
        stderr,
        "CMUXCEFAppGetBrowserProcessHandler self=%p state=%p handlerState=%p handler=%p size=%zu\n",
        self,
        state,
        state != nullptr ? state->browserProcessHandler : nullptr,
        (state != nullptr && state->browserProcessHandler != nullptr) ? &state->browserProcessHandler->handler : nullptr,
        (state != nullptr && state->browserProcessHandler != nullptr) ? state->browserProcessHandler->handler.base.size : 0
    );
#endif
    if (state->browserProcessHandler == nullptr) {
        return nullptr;
    }
    state->browserProcessHandler->handler.base.add_ref(&state->browserProcessHandler->handler.base);
    return &state->browserProcessHandler->handler;
}

static CMUXCEFAppState *CMUXCEFCreateAppState(CEFGlobalRuntimeManager *manager) {
    CMUXCEFBrowserProcessHandlerState *browserProcessHandler = new CMUXCEFBrowserProcessHandlerState();
    browserProcessHandler->handler.base.size = sizeof(cef_browser_process_handler_t);
    browserProcessHandler->handler.base.add_ref = &CMUXCEFBrowserProcessHandlerAddRef;
    browserProcessHandler->handler.base.release = &CMUXCEFBrowserProcessHandlerRelease;
    browserProcessHandler->handler.base.has_one_ref = &CMUXCEFBrowserProcessHandlerHasOneRef;
    browserProcessHandler->handler.base.has_at_least_one_ref = &CMUXCEFBrowserProcessHandlerHasAtLeastOneRef;
    browserProcessHandler->handler.on_context_initialized = &CMUXCEFBrowserProcessHandlerOnContextInitialized;
    browserProcessHandler->handler.on_before_child_process_launch = &CMUXCEFBrowserProcessHandlerOnBeforeChildProcessLaunch;
    browserProcessHandler->handler.on_already_running_app_relaunch = &CMUXCEFBrowserProcessHandlerOnAlreadyRunningAppRelaunch;
    browserProcessHandler->handler.on_schedule_message_pump_work = &CMUXCEFBrowserProcessHandlerOnScheduleMessagePumpWork;
    browserProcessHandler->refCount.store(1);
    browserProcessHandler->manager = manager;

    CMUXCEFAppState *appState = new CMUXCEFAppState();
    appState->app.base.size = sizeof(cef_app_t);
    appState->app.base.add_ref = &CMUXCEFAppAddRef;
    appState->app.base.release = &CMUXCEFAppRelease;
    appState->app.base.has_one_ref = &CMUXCEFAppHasOneRef;
    appState->app.base.has_at_least_one_ref = &CMUXCEFAppHasAtLeastOneRef;
    appState->app.on_before_command_line_processing = &CMUXCEFAppOnBeforeCommandLineProcessing;
    appState->app.get_browser_process_handler = &CMUXCEFAppGetBrowserProcessHandler;
    appState->refCount.store(1);
    appState->browserProcessHandler = browserProcessHandler;
    // Hold the browser-process handler alive for the lifetime of the app state.
    appState->browserProcessHandler->handler.base.add_ref(&appState->browserProcessHandler->handler.base);
    return appState;
}

@interface CEFWorkspaceBridge ()
- (void)handleAutomationConsoleMessage:(NSString *)message;
- (void)handleLoadStartForFrame:(cef_frame_t *)frame;
- (void)loadURLStringInMainFrame:(NSString *)urlString;
- (void)requestContextDidInitialize:(cef_request_context_t *)requestContext;
- (BOOL)runFileDialogWithMode:(cef_file_dialog_mode_t)mode
                        title:(NSString *)title
              defaultFilePath:(NSString *)defaultFilePath
                acceptFilters:(NSArray<NSString *> *)acceptFilters
             acceptExtensions:(NSArray<NSString *> *)acceptExtensions
                     callback:(cef_file_dialog_callback_t *)callback;
- (BOOL)runJavaScriptDialogForOriginURL:(NSString *)originURL
                              dialogType:(cef_jsdialog_type_t)dialogType
                                 message:(NSString *)message
                       defaultPromptText:(NSString *)defaultPromptText
                                callback:(cef_jsdialog_callback_t *)callback
                         suppressMessage:(int *)suppressMessage;
- (BOOL)runBeforeUnloadDialogWithMessage:(NSString *)message
                                isReload:(BOOL)isReload
                                callback:(cef_jsdialog_callback_t *)callback;
- (BOOL)prepareDownloadWithSuggestedName:(NSString *)suggestedName
                            downloadItem:(cef_download_item_t *)downloadItem
                                callback:(cef_before_download_callback_t *)callback;
- (void)updateDownloadItem:(cef_download_item_t *)downloadItem
                  callback:(cef_download_item_callback_t *)callback;
- (void)scheduleFallbackDownloadFinalizeForIdentifier:(NSNumber *)identifierKey;
- (void)finalizeDownloadState:(NSDictionary<NSString *, id> *)downloadState
                identifierKey:(NSNumber *)identifierKey
               suggestedName:(NSString *)suggestedFilename;
@end

@implementation CEFAutomationWaiter
- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _semaphore = dispatch_semaphore_create(0);
    return self;
}
@end

@implementation CEFCookieVisitWaiter
- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _semaphore = dispatch_semaphore_create(0);
    _cookies = [NSMutableArray array];
    _lastUpdateAt = [NSDate date];
    return self;
}
@end

@implementation CEFCookieWriteWaiter
- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _semaphore = dispatch_semaphore_create(0);
    return self;
}
@end

@implementation CEFGlobalRuntimeManager

+ (instancetype)sharedManager {
    static CEFGlobalRuntimeManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[CEFGlobalRuntimeManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    _runtimeStatusSummary = @"CEF runtime not started";
    [self resolveSymbolsIfNeeded];
    return self;
}

- (void)resolveSymbolsIfNeeded {
    if (self.hasRequiredSymbols) {
        return;
    }

    self.apiHashFn = reinterpret_cast<CMUXCEFApiHashFn>(dlsym(RTLD_DEFAULT, "cef_api_hash"));
    self.executeProcessFn = reinterpret_cast<CMUXCEFExecuteProcessFn>(dlsym(RTLD_DEFAULT, "cef_execute_process"));
    self.initializeFn = reinterpret_cast<CMUXCEFInitializeFn>(dlsym(RTLD_DEFAULT, "cef_initialize"));
    self.getExitCodeFn = reinterpret_cast<CMUXCEFGetExitCodeFn>(dlsym(RTLD_DEFAULT, "cef_get_exit_code"));
    self.doMessageLoopWorkFn = reinterpret_cast<CMUXCEFDoMessageLoopWorkFn>(dlsym(RTLD_DEFAULT, "cef_do_message_loop_work"));
    self.shutdownFn = reinterpret_cast<CMUXCEFShutdownFn>(dlsym(RTLD_DEFAULT, "cef_shutdown"));
    self.stringUserfreeFreeFn = reinterpret_cast<CMUXCEFStringUserfreeFreeFn>(dlsym(RTLD_DEFAULT, "cef_string_userfree_utf16_free"));
    self.stringListAllocFn = reinterpret_cast<CMUXCEFStringListAllocFn>(dlsym(RTLD_DEFAULT, "cef_string_list_alloc"));
    self.stringListSizeFn = reinterpret_cast<CMUXCEFStringListSizeFn>(dlsym(RTLD_DEFAULT, "cef_string_list_size"));
    self.stringListValueFn = reinterpret_cast<CMUXCEFStringListValueFn>(dlsym(RTLD_DEFAULT, "cef_string_list_value"));
    self.stringListAppendFn = reinterpret_cast<CMUXCEFStringListAppendFn>(dlsym(RTLD_DEFAULT, "cef_string_list_append"));
    self.stringListFreeFn = reinterpret_cast<CMUXCEFStringListFreeFn>(dlsym(RTLD_DEFAULT, "cef_string_list_free"));
    self.requestContextCreateContextFn = reinterpret_cast<CMUXCEFRequestContextCreateContextFn>(dlsym(RTLD_DEFAULT, "cef_request_context_create_context"));
    self.valueCreateFn = reinterpret_cast<CMUXCEFValueCreateFn>(dlsym(RTLD_DEFAULT, "cef_value_create"));
    self.dictionaryValueCreateFn = reinterpret_cast<CMUXCEFDictionaryValueCreateFn>(dlsym(RTLD_DEFAULT, "cef_dictionary_value_create"));
    self.browserCreateBrowserSyncFn = reinterpret_cast<CMUXCEFBrowserCreateBrowserSyncFn>(dlsym(RTLD_DEFAULT, "cef_browser_host_create_browser_sync"));

    self.hasRequiredSymbols =
        self.apiHashFn != nullptr &&
        self.executeProcessFn != nullptr &&
        self.initializeFn != nullptr &&
        self.doMessageLoopWorkFn != nullptr &&
        self.shutdownFn != nullptr &&
        self.stringUserfreeFreeFn != nullptr &&
        self.stringListAllocFn != nullptr &&
        self.stringListSizeFn != nullptr &&
        self.stringListValueFn != nullptr &&
        self.stringListAppendFn != nullptr &&
        self.stringListFreeFn != nullptr &&
        self.requestContextCreateContextFn != nullptr &&
        self.valueCreateFn != nullptr &&
        self.dictionaryValueCreateFn != nullptr &&
        self.browserCreateBrowserSyncFn != nullptr;

    if (!self.hasRequiredSymbols) {
        self.runtimeStatusSummary = @"CEF symbols unavailable";
    }
}

- (BOOL)ensureStartedWithFrameworkPath:(NSString *)frameworkPath
                         helperAppPath:(nullable NSString *)helperAppPath
                        mainBundlePath:(NSString *)mainBundlePath
                  runtimeCacheRootPath:(NSString *)runtimeCacheRootPath
                      errorDescription:(NSString * _Nullable * _Nullable)errorDescription {
    [self resolveSymbolsIfNeeded];

    if (self.isStarted) {
        if (errorDescription != nullptr) {
            *errorDescription = nil;
        }
        return YES;
    }

    if (!self.hasRequiredSymbols) {
        if (errorDescription != nullptr) {
            *errorDescription = self.runtimeStatusSummary;
        }
        return NO;
    }

    if (self.didAttemptStart) {
        if (errorDescription != nullptr) {
            *errorDescription = self.runtimeStatusSummary;
        }
        return NO;
    }
    self.didAttemptStart = YES;

    const char *apiHash = self.apiHashFn(CMUXCEFAPIVersionExperimental, 0);
    if (apiHash == nullptr) {
        NSString *summary = @"CEF API version configuration failed";
        self.runtimeStatusSummary = summary;
        if (errorDescription != nullptr) {
            *errorDescription = summary;
        }
        return NO;
    }

    NSString *resolvedFrameworkPath = frameworkPath.stringByStandardizingPath;
    NSString *resolvedHelperAppPath = helperAppPath.length > 0
        ? helperAppPath.stringByStandardizingPath
        : @"";
    NSString *resolvedHelperExecutablePath = CMUXCEFHelperExecutablePath(resolvedHelperAppPath) ?: @"";
    NSString *resolvedMainBundlePath = mainBundlePath.length > 0
        ? mainBundlePath.stringByStandardizingPath
        : NSBundle.mainBundle.bundleURL.path.stringByStandardizingPath;
    NSString *rootCachePath = runtimeCacheRootPath.stringByStandardizingPath;
    NSString *profileCachePath = [rootCachePath stringByAppendingPathComponent:@"default"];
    NSString *cefLogPath = [rootCachePath stringByAppendingPathComponent:@"cef-debug.log"];
    NSString *defaultFrameworkPath = [NSBundle.mainBundle.privateFrameworksURL
        URLByAppendingPathComponent:@"Chromium Embedded Framework.framework"
        isDirectory:YES].path.stringByStandardizingPath;
    NSString *defaultFrameworksRoot = NSBundle.mainBundle.privateFrameworksURL.path.stringByStandardizingPath;
    BOOL usesStandardBundleFrameworkLayout =
        CMUXCEFPathEqualsStandardized(resolvedFrameworkPath, defaultFrameworkPath) &&
        CMUXCEFPathHasStandardizedPrefix(resolvedHelperExecutablePath, defaultFrameworksRoot) &&
        [resolvedHelperExecutablePath containsString:@"Helper.app/Contents/MacOS/"];

    NSError *directoryError = nil;
    [NSFileManager.defaultManager createDirectoryAtPath:profileCachePath
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:&directoryError];
    if (directoryError != nil) {
        NSString *summary = [NSString stringWithFormat:@"Failed to prepare CEF cache: %@", directoryError.localizedDescription];
        self.runtimeStatusSummary = summary;
        if (errorDescription != nullptr) {
            *errorDescription = summary;
        }
        return NO;
    }

    if (self.appState == nullptr) {
        self.appState = CMUXCEFCreateAppState(self);
        // Keep the app callbacks alive across execute_process / initialize.
        self.appState->app.base.add_ref(&self.appState->app.base);
    }

    cef_main_args_t mainArgs = CMUXCEFMainArgsFromProcessArguments();
    CMUXCEFDebugLog([NSString stringWithFormat:@"ensureStarted executeProcess framework=%@ helper=%@ cache=%@",
                     resolvedFrameworkPath,
                     resolvedHelperExecutablePath,
                     profileCachePath]);
    int executeResult = self.executeProcessFn(&mainArgs, &self.appState->app, nullptr);
    if (executeResult >= 0) {
        CMUXCEFFreeMainArgs(&mainArgs);
        NSString *summary = [NSString stringWithFormat:@"CEF helper exited early with code %d", executeResult];
        self.runtimeStatusSummary = summary;
        if (errorDescription != nullptr) {
            *errorDescription = summary;
        }
        return NO;
    }

    cef_settings_t settings = {};
    settings.size = sizeof(settings);
    settings.no_sandbox = 1;
    settings.persist_session_cookies = 1;
    settings.external_message_pump = 1;
    if (!usesStandardBundleFrameworkLayout) {
        settings.browser_subprocess_path = CMUXCEFStringFromNSString(resolvedHelperExecutablePath);
        settings.framework_dir_path = CMUXCEFStringFromNSString(resolvedFrameworkPath);
        settings.main_bundle_path = CMUXCEFStringFromNSString(resolvedMainBundlePath);
    }
    settings.cache_path = CMUXCEFStringFromNSString(profileCachePath);
    settings.root_cache_path = CMUXCEFStringFromNSString(rootCachePath);
    settings.log_file = CMUXCEFStringFromNSString(cefLogPath);
    settings.log_severity = LOGSEVERITY_VERBOSE;

    int initializeResult = self.initializeFn(&mainArgs, &settings, &self.appState->app, nullptr);

    CMUXCEFClearString(&settings.browser_subprocess_path);
    CMUXCEFClearString(&settings.framework_dir_path);
    CMUXCEFClearString(&settings.main_bundle_path);
    CMUXCEFClearString(&settings.cache_path);
    CMUXCEFClearString(&settings.root_cache_path);
    CMUXCEFClearString(&settings.log_file);
    CMUXCEFFreeMainArgs(&mainArgs);

    if (initializeResult == 0) {
        NSString *summary = @"CEF failed to initialize";
        if (self.getExitCodeFn != nullptr) {
            summary = [summary stringByAppendingFormat:@" (exit code %d)", self.getExitCodeFn()];
        }
        self.runtimeStatusSummary = summary;
        if (self.appState != nullptr) {
            CMUXCEFReleaseRefCounted(&self.appState->app.base);
            self.appState = nullptr;
        }
        if (errorDescription != nullptr) {
            *errorDescription = self.runtimeStatusSummary;
        }
        return NO;
    }

    self.isStarted = YES;
    [self installTerminateObserver];
    [self requestMessagePumpWorkDelayMS:0];
    self.runtimeStatusSummary = @"CEF runtime running";
    if (errorDescription != nullptr) {
        *errorDescription = nil;
    }
    return YES;
}

- (void)installMessagePump {
    [self requestMessagePumpWorkDelayMS:0];
}

- (void)requestMessagePumpWorkDelayMS:(int64_t)delayMS {
    if (delayMS <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.hasPendingImmediateMessagePumpWork) {
                return;
            }
            self.hasPendingImmediateMessagePumpWork = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.hasPendingImmediateMessagePumpWork = NO;
                [self handleScheduledMessagePumpWorkDelayMS:0];
            });
        });
        return;
    }

    if ([NSThread isMainThread]) {
        [self handleScheduledMessagePumpWorkDelayMS:delayMS];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self handleScheduledMessagePumpWorkDelayMS:delayMS];
    });
}

- (void)handleScheduledMessagePumpWorkDelayMS:(int64_t)delayMS {
    if (!self.isStarted || self.doMessageLoopWorkFn == nullptr) {
        return;
    }

    if (delayMS == CMUXCEFMessagePumpFallbackDelayMS && self.messagePumpTimer != nil) {
        return;
    }

    if (self.messagePumpTimer != nil) {
        [self.messagePumpTimer invalidate];
        self.messagePumpTimer = nil;
    }

    if (delayMS <= 0) {
        BOOL reentrancyDetected = [self performScheduledMessageLoopWork];
        if (reentrancyDetected) {
            [self requestMessagePumpWorkDelayMS:0];
        } else if (self.messagePumpTimer == nil) {
            [self requestMessagePumpWorkDelayMS:CMUXCEFMessagePumpFallbackDelayMS];
        }
        return;
    }

    if (delayMS > CMUXCEFMessagePumpMaxDelayMS) {
        delayMS = CMUXCEFMessagePumpMaxDelayMS;
    }

    __weak typeof(self) weakSelf = self;
    NSTimeInterval interval = (NSTimeInterval)delayMS / 1000.0;
    self.messagePumpTimer = [NSTimer timerWithTimeInterval:interval repeats:NO block:^(__unused NSTimer *timer) {
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf.messagePumpTimer = nil;
        [strongSelf handleScheduledMessagePumpWorkDelayMS:0];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.messagePumpTimer forMode:NSRunLoopCommonModes];
    [NSRunLoop.mainRunLoop addTimer:self.messagePumpTimer forMode:NSEventTrackingRunLoopMode];
}

- (BOOL)performScheduledMessageLoopWork {
    if (!self.isStarted || self.doMessageLoopWorkFn == nullptr) {
        return NO;
    }

    if (self.isPerformingMessageLoopWork) {
        self.messageLoopWorkReentrancyDetected = YES;
        return NO;
    }

    self.isPerformingMessageLoopWork = YES;
    self.messageLoopWorkReentrancyDetected = NO;
    self.doMessageLoopWorkFn();
    self.isPerformingMessageLoopWork = NO;
    return self.messageLoopWorkReentrancyDetected;
}

- (void)installTerminateObserver {
    if (self.terminateObserver != nil) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.terminateObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        __strong typeof(self) strongSelf = weakSelf;
        [strongSelf.messagePumpTimer invalidate];
        strongSelf.messagePumpTimer = nil;
        if (strongSelf.shutdownFn != nullptr && strongSelf.isStarted) {
            strongSelf.shutdownFn();
        }
        if (strongSelf.appState != nullptr) {
            CMUXCEFReleaseRefCounted(&strongSelf.appState->app.base);
            strongSelf.appState = nullptr;
        }
    }];
}

@end

@interface CEFWorkspaceBridge ()
@property(nonatomic, readwrite, copy) NSString *visibleURLString;
@property(nonatomic, readwrite, copy) NSString *socksProxyHost;
@property(nonatomic, readwrite) int32_t socksProxyPort;
@property(nonatomic, readwrite, copy) NSString *cachePath;
@property(nonatomic, readwrite, copy) NSString *currentURLString;
@property(nonatomic, readwrite, copy) NSString *pageTitle;
@property(nonatomic, readwrite) BOOL canGoBack;
@property(nonatomic, readwrite) BOOL canGoForward;
@property(nonatomic, readwrite) BOOL isLoading;
@property(nonatomic, readwrite) BOOL isDownloading;
@property(nonatomic, readwrite) BOOL isBrowserSurfaceFocused;
@property(nonatomic, readwrite) double pageZoomFactor;
@property(nonatomic, readwrite) BOOL runtimeReady;
@property(nonatomic, readwrite, copy) NSString *runtimeStatusSummary;
- (void)containerViewDidMoveToWindow:(CEFBrowserContainerView *)view;
- (void)containerViewDidLayout:(CEFBrowserContainerView *)view;
- (void)containerViewDidBecomeFirstResponder:(CEFBrowserContainerView *)view;
- (void)containerViewDidResignFirstResponder:(CEFBrowserContainerView *)view;
- (void)notifyStateDidChange;
- (void)requestOpenURLInNewTabString:(NSString *)urlString;
- (void)resetFindState;
- (void)updateFindResultsForIdentifier:(int)identifier
                                 count:(int)count
                    activeMatchOrdinal:(int)activeMatchOrdinal;
- (void)handleAutomationConsoleMessage:(NSString *)message;
@end

@implementation CEFBrowserContainerView
- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        _cmuxAllowsFirstResponderAcquisition = YES;
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self.bridge containerViewDidMoveToWindow:self];
}
- (void)layout {
    [super layout];
    [self.bridge containerViewDidLayout:self];
}
- (BOOL)becomeFirstResponder {
    if (!self.cmuxAllowsFirstResponderAcquisitionEffective) {
#if DEBUG
        NSString *eventType = NSApp.currentEvent != nil ? [NSString stringWithFormat:@"%ld", (long)NSApp.currentEvent.type] : @"nil";
        NSLog(
            @"browser.focus.blockedBecome cef=%p policy=%d pointerDepth=%ld eventType=%@",
            self,
            self.cmuxAllowsFirstResponderAcquisition ? 1 : 0,
            (long)self.cmuxDebugPointerFocusAllowanceDepth,
            eventType
        );
#endif
        return NO;
    }
    [self.bridge containerViewDidBecomeFirstResponder:self];
#if DEBUG
    NSString *eventType = NSApp.currentEvent != nil ? [NSString stringWithFormat:@"%ld", (long)NSApp.currentEvent.type] : @"nil";
    NSLog(
        @"browser.focus.become cef=%p result=1 policy=%d pointerDepth=%ld eventType=%@",
        self,
        self.cmuxAllowsFirstResponderAcquisition ? 1 : 0,
        (long)self.cmuxDebugPointerFocusAllowanceDepth,
        eventType
    );
#endif
    return YES;
}
- (BOOL)resignFirstResponder {
    [self.bridge containerViewDidResignFirstResponder:self];
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
#if DEBUG
    NSInteger windowNumber = self.window != nil ? self.window.windowNumber : -1;
    NSString *firstResponderType = self.window.firstResponder != nil ? NSStringFromClass([self.window.firstResponder class]) : @"nil";
    NSLog(
        @"browser.focus.mouseDown cef=%p policy=%d pointerDepth=%ld win=%ld fr=%@",
        self,
        self.cmuxAllowsFirstResponderAcquisition ? 1 : 0,
        (long)self.cmuxDebugPointerFocusAllowanceDepth,
        (long)windowNumber,
        firstResponderType
    );
#endif
    [[NSNotificationCenter defaultCenter] postNotificationName:@"webViewDidReceiveClick"
                                                        object:self];
    [self cmuxBeginPointerFocusAllowance];
    @try {
        [super mouseDown:event];
    } @finally {
        [self cmuxEndPointerFocusAllowance];
    }
}

- (BOOL)cmuxAllowsFirstResponderAcquisitionEffective {
    return self.cmuxAllowsFirstResponderAcquisition || self.cmuxDebugPointerFocusAllowanceDepth > 0;
}

- (void)cmuxBeginPointerFocusAllowance {
    _cmuxDebugPointerFocusAllowanceDepth += 1;
#if DEBUG
    NSLog(
        @"browser.focus.pointerAllowance.enter cef=%p depth=%ld",
        self,
        (long)self.cmuxDebugPointerFocusAllowanceDepth
    );
#endif
}

- (void)cmuxEndPointerFocusAllowance {
    _cmuxDebugPointerFocusAllowanceDepth = MAX(0, _cmuxDebugPointerFocusAllowanceDepth - 1);
#if DEBUG
    NSLog(
        @"browser.focus.pointerAllowance.exit cef=%p depth=%ld",
        self,
        (long)self.cmuxDebugPointerFocusAllowanceDepth
    );
#endif
}

- (NSView *)dragDestinationViewForDraggingInfo:(id<NSDraggingInfo>)sender {
    NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
    NSView *hitView = [self hitTest:point];
    NSView *current = hitView;
    while (current != nil) {
        if (current != self && [current respondsToSelector:@selector(draggingEntered:)]) {
            return current;
        }
        current = current.superview;
    }
    return nil;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSView *target = [self dragDestinationViewForDraggingInfo:sender];
    self.activeDragDestinationView = target;
    if (target != nil && [target respondsToSelector:@selector(draggingEntered:)]) {
        return [(id<NSDraggingDestination>)target draggingEntered:sender];
    }
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    NSView *target = [self dragDestinationViewForDraggingInfo:sender];
    if (self.activeDragDestinationView != nil && self.activeDragDestinationView != target) {
        if ([self.activeDragDestinationView respondsToSelector:@selector(draggingExited:)]) {
            [(id<NSDraggingDestination>)self.activeDragDestinationView draggingExited:sender];
        }
        self.activeDragDestinationView = nil;
    }
    if (target != nil) {
        if (self.activeDragDestinationView != target) {
            self.activeDragDestinationView = target;
            if ([target respondsToSelector:@selector(draggingEntered:)]) {
                return [(id<NSDraggingDestination>)target draggingEntered:sender];
            }
        }
        if ([target respondsToSelector:@selector(draggingUpdated:)]) {
            return [(id<NSDraggingDestination>)target draggingUpdated:sender];
        }
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (void)draggingExited:(nullable id<NSDraggingInfo>)sender {
    if (self.activeDragDestinationView != nil &&
        [self.activeDragDestinationView respondsToSelector:@selector(draggingExited:)]) {
        [(id<NSDraggingDestination>)self.activeDragDestinationView draggingExited:sender];
    }
    self.activeDragDestinationView = nil;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSView *target = self.activeDragDestinationView ?: [self dragDestinationViewForDraggingInfo:sender];
    self.activeDragDestinationView = nil;
    if (target != nil && [target respondsToSelector:@selector(performDragOperation:)]) {
        return [(id<NSDraggingDestination>)target performDragOperation:sender];
    }
    return NO;
}
@end

typedef struct {
    cef_display_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFDisplayHandler;

typedef struct {
    cef_load_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFLoadHandler;

typedef struct {
    cef_life_span_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFLifeSpanHandler;

typedef struct {
    cef_dialog_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFDialogHandler;

typedef struct {
    cef_jsdialog_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFJSDialogHandler;

typedef struct {
    cef_find_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFFindHandler;

typedef struct {
    cef_download_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFDownloadHandler;

typedef struct {
    cef_request_handler_t handler;
    std::atomic<int> refCount;
    __unsafe_unretained CEFWorkspaceBridge *bridge;
} CMUXCEFRequestHandler;

typedef struct {
    cef_request_context_handler_t handler;
    std::atomic<int> refCount;
    __weak CEFWorkspaceBridge *bridge;
} CMUXCEFRequestContextHandler;

typedef struct {
    cef_client_t client;
    std::atomic<int> refCount;
    CMUXCEFDisplayHandler *displayHandler;
    CMUXCEFLoadHandler *loadHandler;
    CMUXCEFLifeSpanHandler *lifeSpanHandler;
    CMUXCEFDialogHandler *dialogHandler;
    CMUXCEFJSDialogHandler *jsDialogHandler;
    CMUXCEFFindHandler *findHandler;
    CMUXCEFDownloadHandler *downloadHandler;
    CMUXCEFRequestHandler *requestHandler;
} CMUXCEFClient;

static CMUXCEFDisplayHandler *CMUXCEFDisplayFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFDisplayHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFDisplayHandler, handler.base));
}

static CMUXCEFLoadHandler *CMUXCEFLoadFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFLoadHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFLoadHandler, handler.base));
}

static CMUXCEFLifeSpanHandler *CMUXCEFLifeSpanFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFLifeSpanHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFLifeSpanHandler, handler.base));
}

static CMUXCEFDialogHandler *CMUXCEFDialogFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFDialogHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFDialogHandler, handler.base));
}

static CMUXCEFJSDialogHandler *CMUXCEFJSDialogFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFJSDialogHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFJSDialogHandler, handler.base));
}

static CMUXCEFFindHandler *CMUXCEFFindFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFFindHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFFindHandler, handler.base));
}

static CMUXCEFDownloadHandler *CMUXCEFDownloadFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFDownloadHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFDownloadHandler, handler.base));
}

static CMUXCEFRequestHandler *CMUXCEFRequestHandlerFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFRequestHandler *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFRequestHandler, handler.base));
}

static CMUXCEFRequestContextHandler *CMUXCEFRequestContextHandlerFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFRequestContextHandler *>(
        reinterpret_cast<char *>(base) - offsetof(CMUXCEFRequestContextHandler, handler.base)
    );
}

static CMUXCEFClient *CMUXCEFClientFromBase(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFClient, client.base));
}

static void CMUXCEFDisplayAddRef(cef_base_ref_counted_t *base) { CMUXCEFDisplayFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFDisplayRelease(cef_base_ref_counted_t *base) {
    CMUXCEFDisplayHandler *handler = CMUXCEFDisplayFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFDisplayHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFDisplayFromBase(base)->refCount.load() == 1; }
static int CMUXCEFDisplayHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFDisplayFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFLoadAddRef(cef_base_ref_counted_t *base) { CMUXCEFLoadFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFLoadRelease(cef_base_ref_counted_t *base) {
    CMUXCEFLoadHandler *handler = CMUXCEFLoadFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFLoadHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFLoadFromBase(base)->refCount.load() == 1; }
static int CMUXCEFLoadHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFLoadFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFLifeSpanAddRef(cef_base_ref_counted_t *base) { CMUXCEFLifeSpanFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFLifeSpanRelease(cef_base_ref_counted_t *base) {
    CMUXCEFLifeSpanHandler *handler = CMUXCEFLifeSpanFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFLifeSpanHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFLifeSpanFromBase(base)->refCount.load() == 1; }
static int CMUXCEFLifeSpanHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFLifeSpanFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFDialogAddRef(cef_base_ref_counted_t *base) { CMUXCEFDialogFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFDialogRelease(cef_base_ref_counted_t *base) {
    CMUXCEFDialogHandler *handler = CMUXCEFDialogFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFDialogHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFDialogFromBase(base)->refCount.load() == 1; }
static int CMUXCEFDialogHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFDialogFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFJSDialogAddRef(cef_base_ref_counted_t *base) { CMUXCEFJSDialogFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFJSDialogRelease(cef_base_ref_counted_t *base) {
    CMUXCEFJSDialogHandler *handler = CMUXCEFJSDialogFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFJSDialogHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFJSDialogFromBase(base)->refCount.load() == 1; }
static int CMUXCEFJSDialogHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFJSDialogFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFFindAddRef(cef_base_ref_counted_t *base) { CMUXCEFFindFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFFindRelease(cef_base_ref_counted_t *base) {
    CMUXCEFFindHandler *handler = CMUXCEFFindFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFFindHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFFindFromBase(base)->refCount.load() == 1; }
static int CMUXCEFFindHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFFindFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFDownloadAddRef(cef_base_ref_counted_t *base) { CMUXCEFDownloadFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFDownloadRelease(cef_base_ref_counted_t *base) {
    CMUXCEFDownloadHandler *handler = CMUXCEFDownloadFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFDownloadHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFDownloadFromBase(base)->refCount.load() == 1; }
static int CMUXCEFDownloadHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFDownloadFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFRequestHandlerAddRef(cef_base_ref_counted_t *base) { CMUXCEFRequestHandlerFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFRequestHandlerRelease(cef_base_ref_counted_t *base) {
    CMUXCEFRequestHandler *handler = CMUXCEFRequestHandlerFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}
static int CMUXCEFRequestHandlerHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFRequestHandlerFromBase(base)->refCount.load() == 1; }
static int CMUXCEFRequestHandlerHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFRequestHandlerFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFRequestContextHandlerAddRef(cef_base_ref_counted_t *base) {
    CMUXCEFRequestContextHandlerFromBase(base)->refCount.fetch_add(1);
}

static int CMUXCEFRequestContextHandlerRelease(cef_base_ref_counted_t *base) {
    CMUXCEFRequestContextHandler *handler = CMUXCEFRequestContextHandlerFromBase(base);
    if (handler->refCount.fetch_sub(1) == 1) {
        delete handler;
        return 1;
    }
    return 0;
}

static int CMUXCEFRequestContextHandlerHasOneRef(cef_base_ref_counted_t *base) {
    return CMUXCEFRequestContextHandlerFromBase(base)->refCount.load() == 1;
}

static int CMUXCEFRequestContextHandlerHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return CMUXCEFRequestContextHandlerFromBase(base)->refCount.load() >= 1;
}

static void CMUXCEFOnRequestContextInitialized(
    cef_request_context_handler_t *self,
    cef_request_context_t *request_context
) {
    CMUXCEFRequestContextHandler *handler = reinterpret_cast<CMUXCEFRequestContextHandler *>(
        reinterpret_cast<char *>(self) - offsetof(CMUXCEFRequestContextHandler, handler)
    );
    CEFWorkspaceBridge *bridge = handler->bridge;
    if (bridge == nil) {
        return;
    }
    [bridge requestContextDidInitialize:request_context];
}

static cef_resource_request_handler_t *CMUXCEFGetRequestContextResourceRequestHandler(
    __unused cef_request_context_handler_t *self,
    __unused cef_browser_t *browser,
    __unused cef_frame_t *frame,
    __unused cef_request_t *request,
    __unused int is_navigation,
    __unused int is_download,
    __unused const cef_string_t *request_initiator,
    __unused int *disable_default_handling
) {
    return nullptr;
}

static void CMUXCEFClientAddRef(cef_base_ref_counted_t *base) { CMUXCEFClientFromBase(base)->refCount.fetch_add(1); }
static int CMUXCEFClientRelease(cef_base_ref_counted_t *base) {
    CMUXCEFClient *client = CMUXCEFClientFromBase(base);
    if (client->refCount.fetch_sub(1) == 1) {
        if (client->displayHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->displayHandler->handler.base);
        }
        if (client->loadHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->loadHandler->handler.base);
        }
        if (client->lifeSpanHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->lifeSpanHandler->handler.base);
        }
        if (client->dialogHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->dialogHandler->handler.base);
        }
        if (client->jsDialogHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->jsDialogHandler->handler.base);
        }
        if (client->findHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->findHandler->handler.base);
        }
        if (client->downloadHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->downloadHandler->handler.base);
        }
        if (client->requestHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&client->requestHandler->handler.base);
        }
        delete client;
        return 1;
    }
    return 0;
}
static int CMUXCEFClientHasOneRef(cef_base_ref_counted_t *base) { return CMUXCEFClientFromBase(base)->refCount.load() == 1; }
static int CMUXCEFClientHasAtLeastOneRef(cef_base_ref_counted_t *base) { return CMUXCEFClientFromBase(base)->refCount.load() >= 1; }

static void CMUXCEFCookieVisitorAddRef(cef_base_ref_counted_t *base) {
    reinterpret_cast<CMUXCEFCookieVisitorState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFCookieVisitorState, visitor))->refCount.fetch_add(1);
}

static int CMUXCEFCookieVisitorRelease(cef_base_ref_counted_t *base) {
    CMUXCEFCookieVisitorState *state = reinterpret_cast<CMUXCEFCookieVisitorState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFCookieVisitorState, visitor));
    if (state->refCount.fetch_sub(1) == 1) {
        delete state;
        return 1;
    }
    return 0;
}

static int CMUXCEFCookieVisitorHasOneRef(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFCookieVisitorState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFCookieVisitorState, visitor))->refCount.load() == 1;
}

static int CMUXCEFCookieVisitorHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFCookieVisitorState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFCookieVisitorState, visitor))->refCount.load() >= 1;
}

static int CMUXCEFCookieVisitorVisit(cef_cookie_visitor_t *self, const cef_cookie_t *cookie, int count, int total, int *deleteCookie) {
    CMUXCEFCookieVisitorState *state = reinterpret_cast<CMUXCEFCookieVisitorState *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFCookieVisitorState, visitor));
    if (state->waiter == nil) {
        return 0;
    }

    NSDictionary *cookieDict = CMUXCEFDictionaryFromCookie(cookie);
    BOOL nameMatches = state->nameFilter.length == 0 || [cookieDict[@"name"] isEqualToString:state->nameFilter];
    BOOL domainMatches = state->domainFilter.length == 0 || [cookieDict[@"domain"] containsString:state->domainFilter];
    BOOL matches = nameMatches && domainMatches;

    state->waiter.sawCookie = YES;
    state->waiter.lastUpdateAt = [NSDate date];
    if (!state->deleteMatches || matches) {
        [state->waiter.cookies addObject:cookieDict];
    }
    if (state->deleteMatches && deleteCookie != nullptr) {
        *deleteCookie = matches ? 1 : 0;
    }

    if (count + 1 >= total) {
        state->waiter.completed = YES;
        dispatch_semaphore_signal(state->waiter.semaphore);
    }
    return 1;
}

static void CMUXCEFSetCookieCallbackAddRef(cef_base_ref_counted_t *base) {
    reinterpret_cast<CMUXCEFSetCookieCallbackState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFSetCookieCallbackState, callback))->refCount.fetch_add(1);
}

static int CMUXCEFSetCookieCallbackRelease(cef_base_ref_counted_t *base) {
    CMUXCEFSetCookieCallbackState *state = reinterpret_cast<CMUXCEFSetCookieCallbackState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFSetCookieCallbackState, callback));
    if (state->refCount.fetch_sub(1) == 1) {
        delete state;
        return 1;
    }
    return 0;
}

static int CMUXCEFSetCookieCallbackHasOneRef(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFSetCookieCallbackState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFSetCookieCallbackState, callback))->refCount.load() == 1;
}

static int CMUXCEFSetCookieCallbackHasAtLeastOneRef(cef_base_ref_counted_t *base) {
    return reinterpret_cast<CMUXCEFSetCookieCallbackState *>(reinterpret_cast<char *>(base) - offsetof(CMUXCEFSetCookieCallbackState, callback))->refCount.load() >= 1;
}

static void CMUXCEFSetCookieCallbackComplete(cef_set_cookie_callback_t *self, int success) {
    CMUXCEFSetCookieCallbackState *state = reinterpret_cast<CMUXCEFSetCookieCallbackState *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFSetCookieCallbackState, callback));
    if (state->waiter == nil) {
        return;
    }
    state->waiter.integerResult = success ? 1 : 0;
    if (!success) {
        state->waiter.errorDescription = @"Failed to set CEF cookie";
    }
    state->waiter.completed = YES;
    dispatch_semaphore_signal(state->waiter.semaphore);
}

static void CMUXCEFBridgeUpdateAddress(CEFWorkspaceBridge *bridge, NSString *url);
static void CMUXCEFBridgeUpdateTitle(CEFWorkspaceBridge *bridge, NSString *title);
static void CMUXCEFBridgeUpdateLoadingState(CEFWorkspaceBridge *bridge, BOOL isLoading, BOOL canGoBack, BOOL canGoForward);
static void CMUXCEFBridgeHandleLoadError(CEFWorkspaceBridge *bridge, NSInteger errorCode, NSString *errorText, NSString *failedURL);
static void CMUXCEFBridgeDidCreateBrowser(CEFWorkspaceBridge *bridge, cef_browser_t *browser);
static void CMUXCEFBridgeWillCloseBrowser(CEFWorkspaceBridge *bridge, cef_browser_t *browser);
static void CMUXCEFBridgeUpdateFindResults(CEFWorkspaceBridge *bridge, int identifier, int count, int activeMatchOrdinal, BOOL finalUpdate);
static double CMUXCEFZoomLevelForPageZoom(double pageZoomFactor);
static double CMUXCEFPageZoomForZoomLevel(double zoomLevel);

static NSString *CMUXCEFFrameURLString(cef_frame_t *frame) {
    if (frame == nullptr || frame->get_url == nullptr) {
        return @"";
    }
    cef_string_userfree_t urlValue = frame->get_url(frame);
    if (urlValue == nullptr) {
        return @"";
    }
    NSString *urlString = CMUXCEFStringToNSString(urlValue);
    if (CEFGlobalRuntimeManager.sharedManager.stringUserfreeFreeFn != nullptr) {
        CEFGlobalRuntimeManager.sharedManager.stringUserfreeFreeFn(urlValue);
    }
    return urlString ?: @"";
}

static NSArray<NSString *> *CMUXCEFArrayFromStringList(cef_string_list_t list) {
    if (list == nullptr || CEFGlobalRuntimeManager.sharedManager.stringListSizeFn == nullptr || CEFGlobalRuntimeManager.sharedManager.stringListValueFn == nullptr) {
        return @[];
    }
    size_t count = CEFGlobalRuntimeManager.sharedManager.stringListSizeFn(list);
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:count];
    for (size_t index = 0; index < count; index++) {
        cef_string_t value = {};
        if (!CEFGlobalRuntimeManager.sharedManager.stringListValueFn(list, index, &value)) {
            continue;
        }
        NSString *stringValue = CMUXCEFStringToNSString(&value);
        CMUXCEFClearString(&value);
        if (stringValue.length > 0) {
            [values addObject:stringValue];
        }
    }
    return values;
}

static cef_string_list_t CMUXCEFCreateStringList(NSArray<NSString *> *values) {
    if (CEFGlobalRuntimeManager.sharedManager.stringListAllocFn == nullptr || CEFGlobalRuntimeManager.sharedManager.stringListAppendFn == nullptr) {
        return nullptr;
    }
    cef_string_list_t list = CEFGlobalRuntimeManager.sharedManager.stringListAllocFn();
    if (list == nullptr) {
        return nullptr;
    }
    for (NSString *value in values) {
        if (value.length == 0) {
            continue;
        }
        cef_string_t cefValue = CMUXCEFStringFromNSString(value);
        CEFGlobalRuntimeManager.sharedManager.stringListAppendFn(list, &cefValue);
        CMUXCEFClearString(&cefValue);
    }
    return list;
}

static NSString *CMUXCEFHTMLDataURLString(NSString *html) {
    NSString *encoded = [html stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    if (encoded.length == 0) {
        return @"";
    }
    return [@"data:text/html;charset=utf-8," stringByAppendingString:encoded];
}

static NSString *CMUXCEFEscapeHTML(NSString *value) {
    NSString *escaped = value ?: @"";
    escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return escaped;
}

static NSURL *CMUXCEFDownloadTempDirectoryURL(void) {
    NSURL *directoryURL = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:@"cmux-downloads" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return directoryURL;
}

static NSURL *CMUXCEFAutoSaveDownloadDirectoryURL(void) {
    NSString *raw = [[[NSProcessInfo processInfo].environment objectForKey:@"CMUX_UI_TEST_BROWSER_DOWNLOAD_DIR"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) {
        return nil;
    }
    NSURL *directoryURL = [NSURL fileURLWithPath:raw isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directoryURL withIntermediateDirectories:YES attributes:nil error:nil];
    return directoryURL;
}

static NSString *CMUXCEFSanitizedDownloadFilename(NSString *raw, NSURL *fallbackURL) {
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *candidate = trimmed.lastPathComponent;
    NSString *fromURL = fallbackURL.lastPathComponent ?: @"";
    NSString *base = candidate.length > 0 ? candidate : fromURL;
    NSString *replaced = [base stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    NSString *safe = [replaced stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return safe.length > 0 ? safe : @"download";
}

static NSArray<NSString *> *CMUXCEFAllowedFileExtensions(NSArray<NSString *> *acceptFilters, NSArray<NSString *> *acceptExtensions) {
    NSMutableOrderedSet<NSString *> *extensions = [NSMutableOrderedSet orderedSet];
    void (^collectExtensionString)(NSString *) = ^(NSString *raw) {
        for (NSString *piece in [raw componentsSeparatedByString:@";"]) {
            NSString *trimmed = [piece stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trimmed.length == 0) {
                continue;
            }
            if ([trimmed containsString:@"|"]) {
                NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@"|"];
                trimmed = parts.lastObject ?: trimmed;
            }
            if ([trimmed hasPrefix:@"."]) {
                trimmed = [trimmed substringFromIndex:1];
            }
            if ([trimmed hasPrefix:@"*." ]) {
                trimmed = [trimmed substringFromIndex:2];
            }
            if (trimmed.length == 0 || [trimmed containsString:@"/"] || [trimmed isEqualToString:@"*"]) {
                continue;
            }
            [extensions addObject:trimmed.lowercaseString];
        }
    };

    for (NSString *entry in acceptExtensions) {
        collectExtensionString(entry);
    }
    for (NSString *entry in acceptFilters) {
        collectExtensionString(entry);
    }

    return extensions.array;
}

static void CMUXCEFApplyAllowedFileExtensionsToPanel(NSSavePanel *panel, NSArray<NSString *> *allowedExtensions) {
    if (allowedExtensions.count == 0) {
        return;
    }
    if (@available(macOS 12.0, *)) {
        NSMutableArray<UTType *> *contentTypes = [NSMutableArray array];
        for (NSString *extension in allowedExtensions) {
            UTType *type = [UTType typeWithFilenameExtension:extension];
            if (type != nil) {
                [contentTypes addObject:type];
            }
        }
        if (contentTypes.count > 0) {
            panel.allowedContentTypes = contentTypes;
            return;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = allowedExtensions;
#pragma clang diagnostic pop
}

static NSString *CMUXCEFJavaScriptDialogTitle(NSString *originURLString) {
    NSURL *url = [NSURL URLWithString:originURLString];
    NSString *absolute = url.absoluteString ?: @"";
    if (absolute.length > 0) {
        return [NSString localizedStringWithFormat:NSLocalizedString(@"browser.dialog.pageSaysAt", nil), absolute];
    }
    return NSLocalizedString(@"browser.dialog.pageSays", nil);
}

static void CMUXCEFOnAddressChange(cef_display_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, const cef_string_t *url) {
    CMUXCEFDisplayHandler *handler = reinterpret_cast<CMUXCEFDisplayHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDisplayHandler, handler));
    if (frame != nullptr && frame->is_main != nullptr && !frame->is_main(frame)) {
        return;
    }
    CMUXCEFBridgeUpdateAddress(handler->bridge, CMUXCEFStringToNSString(url));
}

static void CMUXCEFOnTitleChange(cef_display_handler_t *self, cef_browser_t *browser, const cef_string_t *title) {
    CMUXCEFDisplayHandler *handler = reinterpret_cast<CMUXCEFDisplayHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDisplayHandler, handler));
    CMUXCEFBridgeUpdateTitle(handler->bridge, CMUXCEFStringToNSString(title));
}

static int CMUXCEFOnConsoleMessage(cef_display_handler_t *self, cef_browser_t *browser, cef_log_severity_t level, const cef_string_t *message, const cef_string_t *source, int line) {
    CMUXCEFDisplayHandler *handler = reinterpret_cast<CMUXCEFDisplayHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDisplayHandler, handler));
    [handler->bridge handleAutomationConsoleMessage:CMUXCEFStringToNSString(message)];
    return 0;
}

static void CMUXCEFOnLoadingProgressChange(cef_display_handler_t *self, cef_browser_t *browser, double progress) {
    CMUXCEFDisplayHandler *handler = reinterpret_cast<CMUXCEFDisplayHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDisplayHandler, handler));
    CMUXCEFBridgeUpdateLoadingState(handler->bridge, progress < 1.0, handler->bridge.canGoBack, handler->bridge.canGoForward);
}

static void CMUXCEFOnLoadingStateChange(cef_load_handler_t *self, cef_browser_t *browser, int isLoading, int canGoBack, int canGoForward) {
    CMUXCEFLoadHandler *handler = reinterpret_cast<CMUXCEFLoadHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFLoadHandler, handler));
    CMUXCEFBridgeUpdateLoadingState(handler->bridge, isLoading != 0, canGoBack != 0, canGoForward != 0);
}

static void CMUXCEFOnLoadStart(cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, int transitionType) {
    CMUXCEFLoadHandler *handler = reinterpret_cast<CMUXCEFLoadHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFLoadHandler, handler));
    [handler->bridge handleLoadStartForFrame:frame];
}

static void CMUXCEFOnLoadError(cef_load_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, cef_errorcode_t errorCode, const cef_string_t *errorText, const cef_string_t *failedURL) {
    CMUXCEFLoadHandler *handler = reinterpret_cast<CMUXCEFLoadHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFLoadHandler, handler));
    if (frame != nullptr && frame->is_main != nullptr && !frame->is_main(frame)) {
        return;
    }
    CMUXCEFBridgeHandleLoadError(handler->bridge, errorCode, CMUXCEFStringToNSString(errorText), CMUXCEFStringToNSString(failedURL));
}

static int CMUXCEFOnBeforePopup(cef_life_span_handler_t *self, cef_browser_t *browser, cef_frame_t *frame, int popupID, const cef_string_t *targetURL, const cef_string_t *targetFrameName, int targetDisposition, int userGesture, const void *popupFeatures, cef_window_info_t *windowInfo, cef_client_t **client, cef_browser_settings_t *settings, cef_dictionary_value_t **extraInfo, int *noJavaScriptAccess) {
    CMUXCEFLifeSpanHandler *handler = reinterpret_cast<CMUXCEFLifeSpanHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFLifeSpanHandler, handler));
    NSString *urlString = CMUXCEFStringToNSString(targetURL);
    NSString *sourceFrameURLString = CMUXCEFFrameURLString(frame);
    NSString *resolvedURLString = urlString.length > 0 ? urlString : sourceFrameURLString;
#if DEBUG
    NSLog(
        @"browser.popup.before target=%@ sourceFrame=%@ popupID=%d disposition=%d userGesture=%d resolved=%@",
        urlString,
        sourceFrameURLString,
        popupID,
        targetDisposition,
        userGesture,
        resolvedURLString
    );
#endif
    if (resolvedURLString.length > 0) {
        [handler->bridge requestOpenURLInNewTabString:resolvedURLString];
    }
    return 1;
}

static int CMUXCEFOnFileDialog(cef_dialog_handler_t *self,
                               cef_browser_t *browser,
                               cef_file_dialog_mode_t mode,
                               const cef_string_t *title,
                               const cef_string_t *defaultFilePath,
                               cef_string_list_t acceptFilters,
                               cef_string_list_t acceptExtensions,
                               cef_string_list_t acceptDescriptions,
                               cef_file_dialog_callback_t *callback) {
    CMUXCEFDialogHandler *handler = reinterpret_cast<CMUXCEFDialogHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDialogHandler, handler));
    if (handler->bridge == nil || callback == nullptr) {
        return 0;
    }
    return [handler->bridge runFileDialogWithMode:mode
                                            title:CMUXCEFStringToNSString(title)
                                  defaultFilePath:CMUXCEFStringToNSString(defaultFilePath)
                                    acceptFilters:CMUXCEFArrayFromStringList(acceptFilters)
                                 acceptExtensions:CMUXCEFArrayFromStringList(acceptExtensions)
                                          callback:callback] ? 1 : 0;
}

static int CMUXCEFOnJSDialog(cef_jsdialog_handler_t *self,
                             cef_browser_t *browser,
                             const cef_string_t *originURL,
                             cef_jsdialog_type_t dialogType,
                             const cef_string_t *messageText,
                             const cef_string_t *defaultPromptText,
                             cef_jsdialog_callback_t *callback,
                             int *suppressMessage) {
    CMUXCEFJSDialogHandler *handler = reinterpret_cast<CMUXCEFJSDialogHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFJSDialogHandler, handler));
    if (handler->bridge == nil || callback == nullptr) {
        return 0;
    }
    return [handler->bridge runJavaScriptDialogForOriginURL:CMUXCEFStringToNSString(originURL)
                                                  dialogType:dialogType
                                                     message:CMUXCEFStringToNSString(messageText)
                                           defaultPromptText:CMUXCEFStringToNSString(defaultPromptText)
                                                    callback:callback
                                             suppressMessage:suppressMessage] ? 1 : 0;
}

static int CMUXCEFOnBeforeUnloadDialog(cef_jsdialog_handler_t *self,
                                       cef_browser_t *browser,
                                       const cef_string_t *messageText,
                                       int isReload,
                                       cef_jsdialog_callback_t *callback) {
    CMUXCEFJSDialogHandler *handler = reinterpret_cast<CMUXCEFJSDialogHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFJSDialogHandler, handler));
    if (handler->bridge == nil || callback == nullptr) {
        return 0;
    }
    return [handler->bridge runBeforeUnloadDialogWithMessage:CMUXCEFStringToNSString(messageText)
                                                    isReload:isReload != 0
                                                    callback:callback] ? 1 : 0;
}

static void CMUXCEFOnAfterCreated(cef_life_span_handler_t *self, cef_browser_t *browser) {
    CMUXCEFLifeSpanHandler *handler = reinterpret_cast<CMUXCEFLifeSpanHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFLifeSpanHandler, handler));
    CMUXCEFDebugLog([NSString stringWithFormat:@"lifeSpan.onAfterCreated browser=%p", browser]);
    CMUXCEFBridgeDidCreateBrowser(handler->bridge, browser);
}

static void CMUXCEFOnBeforeClose(cef_life_span_handler_t *self, cef_browser_t *browser) {
    CMUXCEFLifeSpanHandler *handler = reinterpret_cast<CMUXCEFLifeSpanHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFLifeSpanHandler, handler));
    CMUXCEFDebugLog([NSString stringWithFormat:@"lifeSpan.onBeforeClose browser=%p", browser]);
    CMUXCEFBridgeWillCloseBrowser(handler->bridge, browser);
}

static void CMUXCEFOnFindResult(cef_find_handler_t *self, cef_browser_t *browser, int identifier, int count, const cef_rect_t *selectionRect, int activeMatchOrdinal, int finalUpdate) {
    CMUXCEFFindHandler *handler = reinterpret_cast<CMUXCEFFindHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFFindHandler, handler));
    CMUXCEFBridgeUpdateFindResults(handler->bridge, identifier, count, activeMatchOrdinal, finalUpdate != 0);
}

static int CMUXCEFCanDownload(cef_download_handler_t *self, __unused cef_browser_t *browser, __unused const cef_string_t *url, __unused const cef_string_t *request_method) {
    CMUXCEFDownloadHandler *handler = reinterpret_cast<CMUXCEFDownloadHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDownloadHandler, handler));
    return handler->bridge != nil ? 1 : 0;
}

static int CMUXCEFOnBeforeDownload(
    cef_download_handler_t *self,
    __unused cef_browser_t *browser,
    cef_download_item_t *download_item,
    const cef_string_t *suggested_name,
    cef_before_download_callback_t *callback
) {
    CMUXCEFDownloadHandler *handler = reinterpret_cast<CMUXCEFDownloadHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDownloadHandler, handler));
    if (handler->bridge == nil) {
        return 0;
    }
    return [handler->bridge prepareDownloadWithSuggestedName:CMUXCEFStringToNSString(suggested_name)
                                                downloadItem:download_item
                                                    callback:callback] ? 1 : 0;
}

static void CMUXCEFOnDownloadUpdated(
    cef_download_handler_t *self,
    __unused cef_browser_t *browser,
    cef_download_item_t *download_item,
    cef_download_item_callback_t *callback
) {
    CMUXCEFDownloadHandler *handler = reinterpret_cast<CMUXCEFDownloadHandler *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFDownloadHandler, handler));
    if (handler->bridge == nil) {
        return;
    }
    [handler->bridge updateDownloadItem:download_item callback:callback];
}

static int CMUXCEFOnSelectClientCertificate(
    cef_request_handler_t *self,
    __unused cef_browser_t *browser,
    int isProxy,
    const cef_string_t *host,
    int port,
    size_t certificatesCount,
    __unused cef_x509_certificate_t *const *certificates,
    __unused cef_select_client_certificate_callback_t *callback
) {
    CMUXCEFRequestHandler *handler = reinterpret_cast<CMUXCEFRequestHandler *>(
        reinterpret_cast<char *>(self) - offsetof(CMUXCEFRequestHandler, handler)
    );
    CMUXCEFDebugLog([NSString stringWithFormat:
                     @"requestHandler on_select_client_certificate host=%@ port=%d proxy=%d count=%zu default=1 bridge=%@",
                     CMUXCEFStringToNSString(host),
                     port,
                     isProxy,
                     certificatesCount,
                     handler->bridge != nil ? @"yes" : @"no"]);
    return 0;
}

static cef_display_handler_t *CMUXCEFClientGetDisplayHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->displayHandler != nullptr) {
        client->displayHandler->handler.base.add_ref(&client->displayHandler->handler.base);
        return &client->displayHandler->handler;
    }
    return nullptr;
}

static cef_load_handler_t *CMUXCEFClientGetLoadHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->loadHandler != nullptr) {
        client->loadHandler->handler.base.add_ref(&client->loadHandler->handler.base);
        return &client->loadHandler->handler;
    }
    return nullptr;
}

static cef_download_handler_t *CMUXCEFClientGetDownloadHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->downloadHandler != nullptr) {
        client->downloadHandler->handler.base.add_ref(&client->downloadHandler->handler.base);
        return &client->downloadHandler->handler;
    }
    return nullptr;
}

static cef_life_span_handler_t *CMUXCEFClientGetLifeSpanHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->lifeSpanHandler != nullptr) {
        client->lifeSpanHandler->handler.base.add_ref(&client->lifeSpanHandler->handler.base);
        return &client->lifeSpanHandler->handler;
    }
    return nullptr;
}

static cef_dialog_handler_t *CMUXCEFClientGetDialogHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->dialogHandler != nullptr) {
        client->dialogHandler->handler.base.add_ref(&client->dialogHandler->handler.base);
        return &client->dialogHandler->handler;
    }
    return nullptr;
}

static cef_jsdialog_handler_t *CMUXCEFClientGetJSDialogHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->jsDialogHandler != nullptr) {
        client->jsDialogHandler->handler.base.add_ref(&client->jsDialogHandler->handler.base);
        return &client->jsDialogHandler->handler;
    }
    return nullptr;
}

static cef_find_handler_t *CMUXCEFClientGetFindHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->findHandler != nullptr) {
        client->findHandler->handler.base.add_ref(&client->findHandler->handler.base);
        return &client->findHandler->handler;
    }
    return nullptr;
}

static cef_request_handler_t *CMUXCEFClientGetRequestHandler(cef_client_t *self) {
    CMUXCEFClient *client = reinterpret_cast<CMUXCEFClient *>(reinterpret_cast<char *>(self) - offsetof(CMUXCEFClient, client));
    if (client->requestHandler != nullptr) {
        client->requestHandler->handler.base.add_ref(&client->requestHandler->handler.base);
        return &client->requestHandler->handler;
    }
    return nullptr;
}

static CMUXCEFDisplayHandler *CMUXCEFCreateDisplayHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFDisplayHandler *handler = new CMUXCEFDisplayHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_display_handler_t);
    handler->handler.base.add_ref = &CMUXCEFDisplayAddRef;
    handler->handler.base.release = &CMUXCEFDisplayRelease;
    handler->handler.base.has_one_ref = &CMUXCEFDisplayHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFDisplayHasAtLeastOneRef;
    handler->handler.on_address_change = &CMUXCEFOnAddressChange;
    handler->handler.on_title_change = &CMUXCEFOnTitleChange;
    handler->handler.on_console_message = &CMUXCEFOnConsoleMessage;
    handler->handler.on_loading_progress_change = &CMUXCEFOnLoadingProgressChange;
    return handler;
}

static CMUXCEFLoadHandler *CMUXCEFCreateLoadHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFLoadHandler *handler = new CMUXCEFLoadHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_load_handler_t);
    handler->handler.base.add_ref = &CMUXCEFLoadAddRef;
    handler->handler.base.release = &CMUXCEFLoadRelease;
    handler->handler.base.has_one_ref = &CMUXCEFLoadHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFLoadHasAtLeastOneRef;
    handler->handler.on_loading_state_change = &CMUXCEFOnLoadingStateChange;
    handler->handler.on_load_start = &CMUXCEFOnLoadStart;
    handler->handler.on_load_error = &CMUXCEFOnLoadError;
    return handler;
}

static CMUXCEFLifeSpanHandler *CMUXCEFCreateLifeSpanHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFLifeSpanHandler *handler = new CMUXCEFLifeSpanHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_life_span_handler_t);
    handler->handler.base.add_ref = &CMUXCEFLifeSpanAddRef;
    handler->handler.base.release = &CMUXCEFLifeSpanRelease;
    handler->handler.base.has_one_ref = &CMUXCEFLifeSpanHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFLifeSpanHasAtLeastOneRef;
    handler->handler.on_before_popup = &CMUXCEFOnBeforePopup;
    handler->handler.on_after_created = &CMUXCEFOnAfterCreated;
    handler->handler.on_before_close = &CMUXCEFOnBeforeClose;
    return handler;
}

static CMUXCEFDialogHandler *CMUXCEFCreateDialogHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFDialogHandler *handler = new CMUXCEFDialogHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_dialog_handler_t);
    handler->handler.base.add_ref = &CMUXCEFDialogAddRef;
    handler->handler.base.release = &CMUXCEFDialogRelease;
    handler->handler.base.has_one_ref = &CMUXCEFDialogHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFDialogHasAtLeastOneRef;
    handler->handler.on_file_dialog = &CMUXCEFOnFileDialog;
    return handler;
}

static CMUXCEFJSDialogHandler *CMUXCEFCreateJSDialogHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFJSDialogHandler *handler = new CMUXCEFJSDialogHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_jsdialog_handler_t);
    handler->handler.base.add_ref = &CMUXCEFJSDialogAddRef;
    handler->handler.base.release = &CMUXCEFJSDialogRelease;
    handler->handler.base.has_one_ref = &CMUXCEFJSDialogHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFJSDialogHasAtLeastOneRef;
    handler->handler.on_jsdialog = &CMUXCEFOnJSDialog;
    handler->handler.on_before_unload_dialog = &CMUXCEFOnBeforeUnloadDialog;
    return handler;
}

static CMUXCEFFindHandler *CMUXCEFCreateFindHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFFindHandler *handler = new CMUXCEFFindHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_find_handler_t);
    handler->handler.base.add_ref = &CMUXCEFFindAddRef;
    handler->handler.base.release = &CMUXCEFFindRelease;
    handler->handler.base.has_one_ref = &CMUXCEFFindHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFFindHasAtLeastOneRef;
    handler->handler.on_find_result = &CMUXCEFOnFindResult;
    return handler;
}

static CMUXCEFDownloadHandler *CMUXCEFCreateDownloadHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFDownloadHandler *handler = new CMUXCEFDownloadHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_download_handler_t);
    handler->handler.base.add_ref = &CMUXCEFDownloadAddRef;
    handler->handler.base.release = &CMUXCEFDownloadRelease;
    handler->handler.base.has_one_ref = &CMUXCEFDownloadHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFDownloadHasAtLeastOneRef;
    handler->handler.can_download = &CMUXCEFCanDownload;
    handler->handler.on_before_download = &CMUXCEFOnBeforeDownload;
    handler->handler.on_download_updated = &CMUXCEFOnDownloadUpdated;
    return handler;
}

static CMUXCEFRequestHandler *CMUXCEFCreateRequestHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFRequestHandler *handler = new CMUXCEFRequestHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_request_handler_t);
    handler->handler.base.add_ref = &CMUXCEFRequestHandlerAddRef;
    handler->handler.base.release = &CMUXCEFRequestHandlerRelease;
    handler->handler.base.has_one_ref = &CMUXCEFRequestHandlerHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFRequestHandlerHasAtLeastOneRef;
    handler->handler.on_select_client_certificate = &CMUXCEFOnSelectClientCertificate;
    return handler;
}

static CMUXCEFClient *CMUXCEFCreateClient(CEFWorkspaceBridge *bridge) {
    CMUXCEFClient *client = new CMUXCEFClient();
    client->refCount.store(1);
    client->displayHandler = CMUXCEFCreateDisplayHandler(bridge);
    client->loadHandler = CMUXCEFCreateLoadHandler(bridge);
    client->lifeSpanHandler = CMUXCEFCreateLifeSpanHandler(bridge);
    client->dialogHandler = CMUXCEFCreateDialogHandler(bridge);
    client->jsDialogHandler = CMUXCEFCreateJSDialogHandler(bridge);
    client->findHandler = CMUXCEFCreateFindHandler(bridge);
    client->downloadHandler = CMUXCEFCreateDownloadHandler(bridge);
    client->requestHandler = CMUXCEFCreateRequestHandler(bridge);
    client->client.base.size = sizeof(cef_client_t);
    client->client.base.add_ref = &CMUXCEFClientAddRef;
    client->client.base.release = &CMUXCEFClientRelease;
    client->client.base.has_one_ref = &CMUXCEFClientHasOneRef;
    client->client.base.has_at_least_one_ref = &CMUXCEFClientHasAtLeastOneRef;
    client->client.get_dialog_handler = &CMUXCEFClientGetDialogHandler;
    client->client.get_display_handler = &CMUXCEFClientGetDisplayHandler;
    client->client.get_download_handler = &CMUXCEFClientGetDownloadHandler;
    client->client.get_find_handler = &CMUXCEFClientGetFindHandler;
    client->client.get_jsdialog_handler = &CMUXCEFClientGetJSDialogHandler;
    client->client.get_life_span_handler = &CMUXCEFClientGetLifeSpanHandler;
    client->client.get_load_handler = &CMUXCEFClientGetLoadHandler;
    client->client.get_request_handler = &CMUXCEFClientGetRequestHandler;
    return client;
}

static CMUXCEFRequestContextHandler *CMUXCEFCreateRequestContextHandler(CEFWorkspaceBridge *bridge) {
    CMUXCEFRequestContextHandler *handler = new CMUXCEFRequestContextHandler();
    handler->refCount.store(1);
    handler->bridge = bridge;
    handler->handler.base.size = sizeof(cef_request_context_handler_t);
    handler->handler.base.add_ref = &CMUXCEFRequestContextHandlerAddRef;
    handler->handler.base.release = &CMUXCEFRequestContextHandlerRelease;
    handler->handler.base.has_one_ref = &CMUXCEFRequestContextHandlerHasOneRef;
    handler->handler.base.has_at_least_one_ref = &CMUXCEFRequestContextHandlerHasAtLeastOneRef;
    handler->handler.on_request_context_initialized = &CMUXCEFOnRequestContextInitialized;
    handler->handler.get_resource_request_handler = &CMUXCEFGetRequestContextResourceRequestHandler;
    return handler;
}

@implementation CEFWorkspaceBridge {
    NSString *_frameworkPath;
    NSString *_helperAppPath;
    NSString *_mainBundlePath;
    NSString *_runtimeCacheRootPath;
    CEFBrowserContainerView *_browserView;
    NSTextField *_statusLabel;
    cef_browser_t *_browser;
    cef_request_context_t *_requestContext;
    CMUXCEFRequestContextHandler *_requestContextHandler;
    BOOL _requestContextInitialized;
    CMUXCEFClient *_client;
    NSString *_activeFindQuery;
    int _activeFindIdentifier;
    NSMutableDictionary<NSString *, CEFAutomationWaiter *> *_automationWaitersByToken;
    NSMutableArray<NSString *> *_documentStartScripts;
    NSMutableDictionary<NSNumber *, NSDictionary<NSString *, id> *> *_downloadStatesByIdentifier;
}

@synthesize findMatchCount = _findMatchCount;
@synthesize selectedFindMatchOrdinal = _selectedFindMatchOrdinal;

static NSString *CMUXCEFCanonicalPath(NSString *path) {
    if (path.length == 0) {
        return path;
    }
    return [[[NSURL fileURLWithPath:path isDirectory:NO] URLByResolvingSymlinksInPath] path].stringByStandardizingPath;
}

static NSString *CMUXCEFDebugLogPath(void) {
    NSString *overridePath = [[[NSProcessInfo processInfo].environment objectForKey:@"CMUX_CEF_LOG_PATH"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (overridePath.length > 0) {
        return overridePath;
    }

    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"cmux";
    NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowed addCharactersInString:@"-"];
    NSMutableString *sanitized = [NSMutableString stringWithCapacity:bundleIdentifier.length];
    for (NSUInteger index = 0; index < bundleIdentifier.length; index += 1) {
        unichar character = [bundleIdentifier characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [sanitized appendFormat:@"%C", character];
        } else {
            [sanitized appendString:@"-"];
        }
    }

    return [@"/tmp" stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-cef.log", sanitized]];
}

static void CMUXCEFDebugLog(NSString *message) {
    NSLog(@"[CEFBridge] %@", message);
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    NSString *line = [NSString stringWithFormat:@"%@ [CEFBridge] %@\n",
                      [formatter stringFromDate:[NSDate date]],
                      message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return;
    }

    NSString *logPath = CMUXCEFDebugLogPath();
    int fd = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) {
        return;
    }

    ssize_t remaining = (ssize_t)data.length;
    const uint8_t *cursor = reinterpret_cast<const uint8_t *>(data.bytes);
    while (remaining > 0) {
        ssize_t written = write(fd, cursor, (size_t)remaining);
        if (written <= 0) {
            break;
        }
        cursor += written;
        remaining -= written;
    }

    close(fd);
}

+ (BOOL)isRuntimeLinked {
    return CEFGlobalRuntimeManager.sharedManager.hasRequiredSymbols;
}

+ (NSString *)runtimeStatusSummary {
    return CEFGlobalRuntimeManager.sharedManager.runtimeStatusSummary;
}

+ (BOOL)ensureGlobalRuntimeWithFrameworkPath:(NSString *)frameworkPath
                               helperAppPath:(nullable NSString *)helperAppPath
                              mainBundlePath:(NSString *)mainBundlePath
                        runtimeCacheRootPath:(NSString *)runtimeCacheRootPath
                            errorDescription:(NSString * _Nullable * _Nullable)errorDescription {
    return [CEFGlobalRuntimeManager.sharedManager ensureStartedWithFrameworkPath:frameworkPath helperAppPath:helperAppPath mainBundlePath:mainBundlePath runtimeCacheRootPath:runtimeCacheRootPath errorDescription:errorDescription];
}

- (instancetype)initWithVisibleURLString:(NSString *)visibleURLString
                          socksProxyHost:(NSString *)socksProxyHost
                          socksProxyPort:(int32_t)socksProxyPort
                               cachePath:(NSString *)cachePath
                           frameworkPath:(NSString *)frameworkPath
                           helperAppPath:(nullable NSString *)helperAppPath
                          mainBundlePath:(NSString *)mainBundlePath
                     runtimeCacheRootPath:(NSString *)runtimeCacheRootPath {
    self = [super init];
    if (!self) {
        return nil;
    }

    _visibleURLString = [visibleURLString copy];
    _socksProxyHost = [socksProxyHost copy];
    _socksProxyPort = socksProxyPort;
    _cachePath = [CMUXCEFCanonicalPath(cachePath) copy];
    _currentURLString = [visibleURLString copy];
    _pageTitle = @"CEF";
    _pageZoomFactor = 1.0;
    _frameworkPath = [CMUXCEFCanonicalPath(frameworkPath) copy];
    _helperAppPath = [CMUXCEFCanonicalPath(helperAppPath ?: @"") copy];
    _mainBundlePath = [CMUXCEFCanonicalPath(mainBundlePath) copy];
    _runtimeCacheRootPath = [CMUXCEFCanonicalPath(runtimeCacheRootPath) copy];
    _runtimeStatusSummary = CEFGlobalRuntimeManager.sharedManager.runtimeStatusSummary ?: @"CEF runtime not started";

    NSString *errorDescription = nil;
    _runtimeReady = [CEFGlobalRuntimeManager.sharedManager ensureStartedWithFrameworkPath:_frameworkPath helperAppPath:_helperAppPath mainBundlePath:_mainBundlePath runtimeCacheRootPath:_runtimeCacheRootPath errorDescription:&errorDescription];
    _runtimeStatusSummary = errorDescription ?: CEFGlobalRuntimeManager.sharedManager.runtimeStatusSummary ?: _runtimeStatusSummary;
    CMUXCEFDebugLog([NSString stringWithFormat:@"init runtimeReady=%d cachePath=%@ proxy=%@:%d runtimeStatus=%@",
                     _runtimeReady ? 1 : 0,
                     _cachePath,
                     _socksProxyHost,
                     _socksProxyPort,
                     _runtimeStatusSummary]);

    if (_runtimeReady) {
        _client = CMUXCEFCreateClient(self);
        [self createRequestContextIfNeeded];
    }
    _automationWaitersByToken = [NSMutableDictionary dictionary];
    _documentStartScripts = [NSMutableArray array];
    _downloadStatesByIdentifier = [NSMutableDictionary dictionary];

    return self;
}

- (void)dealloc {
    [self tearDownBrowser];
    if (_client != nullptr) {
        CMUXCEFReleaseRefCounted(&_client->client.base);
        _client = nullptr;
    }
}

- (NSView *)makeBrowserView {
    if (_browserView == nil) {
        CMUXCEFDebugLog([NSString stringWithFormat:@"makeBrowserView create runtimeReady=%d currentURL=%@",
                         _runtimeReady ? 1 : 0,
                         self.currentURLString]);
        _browserView = [[CEFBrowserContainerView alloc] initWithFrame:NSZeroRect];
        _browserView.bridge = self;
        _browserView.identifier = @"CEFWorkspaceBridgeHost";
        _browserView.wantsLayer = YES;
        _browserView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    }
    [self updateStatusLabel];
    return _browserView;
}

- (void)navigateToURLString:(NSString *)urlString {
    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return;
    }
    self.currentURLString = trimmed;
    _findMatchCount = 0;
    _selectedFindMatchOrdinal = 0;
    if (_browser != nullptr && _browser->get_main_frame != nullptr) {
        cef_frame_t *frame = _browser->get_main_frame(_browser);
        if (frame != nullptr && frame->load_url != nullptr) {
            cef_string_t cefURL = CMUXCEFStringFromNSString(trimmed);
            frame->load_url(frame, &cefURL);
            CMUXCEFClearString(&cefURL);
            CMUXCEFReleaseRefCounted(&frame->base);
        }
    }
    [self updateStatusLabel];
    [self notifyStateDidChange];
}

- (void)loadURLStringInMainFrame:(NSString *)urlString {
    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || _browser == nullptr || _browser->get_main_frame == nullptr) {
        return;
    }
    cef_frame_t *frame = _browser->get_main_frame(_browser);
    if (frame != nullptr && frame->load_url != nullptr) {
        cef_string_t cefURL = CMUXCEFStringFromNSString(trimmed);
        frame->load_url(frame, &cefURL);
        CMUXCEFClearString(&cefURL);
        CMUXCEFReleaseRefCounted(&frame->base);
    }
}

- (BOOL)runFileDialogWithMode:(cef_file_dialog_mode_t)mode
                        title:(NSString *)title
              defaultFilePath:(NSString *)defaultFilePath
                acceptFilters:(NSArray<NSString *> *)acceptFilters
             acceptExtensions:(NSArray<NSString *> *)acceptExtensions
                     callback:(cef_file_dialog_callback_t *)callback {
    if (callback == nullptr) {
        return NO;
    }
    if (callback->base.add_ref == nullptr || callback->base.release == nullptr) {
        return NO;
    }

    callback->base.add_ref(&callback->base);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray<NSString *> *allowedExtensions = CMUXCEFAllowedFileExtensions(acceptFilters, acceptExtensions);
        NSString *effectiveTitle = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *trimmedDefaultPath = [defaultFilePath stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSURL *defaultURL = trimmedDefaultPath.length > 0 ? [NSURL fileURLWithPath:trimmedDefaultPath] : nil;
        NSWindow *window = self->_browserView.window;

        void (^finishWithURLs)(NSArray<NSURL *> *) = ^(NSArray<NSURL *> *urls) {
            if (urls.count == 0) {
                if (callback->cancel != nullptr) {
                    callback->cancel(callback);
                }
            } else if (callback->cont != nullptr) {
                NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:urls.count];
                for (NSURL *url in urls) {
                    if (url.path.length > 0) {
                        [paths addObject:url.path];
                    }
                }
                if (paths.count == 0) {
                    if (callback->cancel != nullptr) {
                        callback->cancel(callback);
                    }
                } else {
                    cef_string_list_t stringList = CMUXCEFCreateStringList(paths);
                    if (stringList != nullptr) {
                        callback->cont(callback, stringList);
                        if (CEFGlobalRuntimeManager.sharedManager.stringListFreeFn != nullptr) {
                            CEFGlobalRuntimeManager.sharedManager.stringListFreeFn(stringList);
                        }
                    } else if (callback->cancel != nullptr) {
                        callback->cancel(callback);
                    }
                }
            }
            callback->base.release(&callback->base);
        };

        if (mode == FILE_DIALOG_SAVE) {
            NSSavePanel *panel = [NSSavePanel savePanel];
            panel.title = effectiveTitle.length > 0 ? effectiveTitle : NSLocalizedString(@"settings.browser.httpAllowlist.save", nil);
            if (defaultURL != nil) {
                NSURL *directoryURL = defaultURL.hasDirectoryPath ? defaultURL : defaultURL.URLByDeletingLastPathComponent;
                if (directoryURL != nil) {
                    panel.directoryURL = directoryURL;
                }
                if (!defaultURL.hasDirectoryPath && defaultURL.lastPathComponent.length > 0) {
                    panel.nameFieldStringValue = defaultURL.lastPathComponent;
                }
            }
            CMUXCEFApplyAllowedFileExtensionsToPanel(panel, allowedExtensions);
            void (^handler)(NSModalResponse) = ^(NSModalResponse result) {
                finishWithURLs(result == NSModalResponseOK && panel.URL != nil ? @[panel.URL] : @[]);
            };
            if (window != nil) {
                [panel beginSheetModalForWindow:window completionHandler:handler];
            } else {
                [panel beginWithCompletionHandler:handler];
            }
            return;
        }

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.title = effectiveTitle.length > 0 ? effectiveTitle : NSLocalizedString(@"panel.openFolder.prompt", nil);
        panel.allowsMultipleSelection = (mode == FILE_DIALOG_OPEN_MULTIPLE);
        panel.canChooseDirectories = (mode == FILE_DIALOG_OPEN_FOLDER);
        panel.canChooseFiles = (mode != FILE_DIALOG_OPEN_FOLDER);
        if (defaultURL != nil) {
            panel.directoryURL = defaultURL.hasDirectoryPath ? defaultURL : defaultURL.URLByDeletingLastPathComponent;
        }
        if (mode != FILE_DIALOG_OPEN_FOLDER) {
            CMUXCEFApplyAllowedFileExtensionsToPanel(panel, allowedExtensions);
        }
        void (^handler)(NSModalResponse) = ^(NSModalResponse result) {
            finishWithURLs(result == NSModalResponseOK ? panel.URLs : @[]);
        };
        if (window != nil) {
            [panel beginSheetModalForWindow:window completionHandler:handler];
        } else {
            [panel beginWithCompletionHandler:handler];
        }
    });
    return YES;
}

- (BOOL)runJavaScriptDialogForOriginURL:(NSString *)originURL
                              dialogType:(cef_jsdialog_type_t)dialogType
                                 message:(NSString *)message
                       defaultPromptText:(NSString *)defaultPromptText
                                callback:(cef_jsdialog_callback_t *)callback
                         suppressMessage:(int *)suppressMessage {
    if (callback == nullptr || callback->base.add_ref == nullptr || callback->base.release == nullptr || callback->cont == nullptr) {
        return NO;
    }
    if (suppressMessage != nullptr) {
        *suppressMessage = 0;
    }

    callback->base.add_ref(&callback->base);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleInformational;
        alert.messageText = CMUXCEFJavaScriptDialogTitle(originURL);
        alert.informativeText = message ?: @"";
        [alert addButtonWithTitle:NSLocalizedString(@"common.ok", nil)];
        if (dialogType != JSDIALOGTYPE_ALERT) {
            [alert addButtonWithTitle:NSLocalizedString(@"common.cancel", nil)];
        }

        NSTextField *inputField = nil;
        if (dialogType == JSDIALOGTYPE_PROMPT) {
            inputField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
            inputField.stringValue = defaultPromptText ?: @"";
            alert.accessoryView = inputField;
        }

        void (^finish)(NSModalResponse) = ^(NSModalResponse result) {
            BOOL confirmed = (result == NSAlertFirstButtonReturn);
            cef_string_t userInput = {};
            const cef_string_t *userInputPtr = nullptr;
            if (dialogType == JSDIALOGTYPE_PROMPT && confirmed) {
                userInput = CMUXCEFStringFromNSString(inputField.stringValue ?: @"");
                userInputPtr = &userInput;
            }
            callback->cont(callback, confirmed ? 1 : 0, userInputPtr);
            CMUXCEFClearString(&userInput);
            callback->base.release(&callback->base);
        };

        NSWindow *window = self->_browserView.window;
        if (window != nil) {
            [alert beginSheetModalForWindow:window completionHandler:finish];
        } else {
            finish([alert runModal]);
        }
    });
    return YES;
}

- (BOOL)runBeforeUnloadDialogWithMessage:(NSString *)message
                                isReload:(BOOL)isReload
                                callback:(cef_jsdialog_callback_t *)callback {
    return [self runJavaScriptDialogForOriginURL:@""
                                      dialogType:JSDIALOGTYPE_CONFIRM
                                         message:message
                               defaultPromptText:@""
                                        callback:callback
                                 suppressMessage:nullptr];
}

- (BOOL)prepareDownloadWithSuggestedName:(NSString *)suggestedName
                            downloadItem:(cef_download_item_t *)downloadItem
                                callback:(cef_before_download_callback_t *)callback {
    if (downloadItem == nullptr || callback == nullptr || callback->cont == nullptr ||
        callback->base.add_ref == nullptr || callback->base.release == nullptr) {
        return NO;
    }

    callback->base.add_ref(&callback->base);
    NSString *requestedName = [suggestedName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *fallbackURLString = downloadItem->get_original_url != nullptr
        ? CMUXCEFStringToNSString(downloadItem->get_original_url(downloadItem))
        : @"";
    if (requestedName.length == 0 && downloadItem->get_suggested_file_name != nullptr) {
        requestedName = CMUXCEFStringToNSString(downloadItem->get_suggested_file_name(downloadItem));
    }
    NSURL *fallbackURL = fallbackURLString.length > 0 ? [NSURL URLWithString:fallbackURLString] : nil;
    NSString *safeFilename = CMUXCEFSanitizedDownloadFilename(requestedName, fallbackURL);
    NSURL *autoSaveDirectoryURL = CMUXCEFAutoSaveDownloadDirectoryURL();
    NSURL *downloadURL = autoSaveDirectoryURL != nil
        ? [autoSaveDirectoryURL URLByAppendingPathComponent:safeFilename isDirectory:NO]
        : [CMUXCEFDownloadTempDirectoryURL()
            URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, safeFilename]
                               isDirectory:NO];
    [NSFileManager.defaultManager removeItemAtURL:downloadURL error:nil];

    uint32_t downloadIdentifier = downloadItem->get_id != nullptr ? downloadItem->get_id(downloadItem) : 0;
    NSNumber *identifierKey = @(downloadIdentifier);
    NSMutableDictionary<NSString *, id> *downloadState = [@{
        @"suggestedFilename": safeFilename,
        @"attempts": @0,
        @"lastObservedSize": @(-1),
    } mutableCopy];
    if (autoSaveDirectoryURL != nil) {
        downloadState[@"directSaveURL"] = downloadURL;
    } else {
        downloadState[@"tempURL"] = downloadURL;
    }
    @synchronized(self) {
        self->_downloadStatesByIdentifier[identifierKey] = downloadState;
    }

    CMUXCEFDebugLog([NSString stringWithFormat:@"download.onBefore id=%u file=%@ path=%@ direct=%d",
                     downloadIdentifier,
                     safeFilename,
                     downloadURL.path,
                     autoSaveDirectoryURL != nil ? 1 : 0]);

    cef_string_t downloadPath = CMUXCEFStringFromNSString(downloadURL.path);
    callback->cont(callback, &downloadPath, 0);
    CMUXCEFClearString(&downloadPath);
    callback->base.release(&callback->base);

    dispatch_async(dispatch_get_main_queue(), ^{
        self.isDownloading = YES;
        self.runtimeStatusSummary = [NSString stringWithFormat:@"Downloading %@", safeFilename];
        [self updateStatusLabel];
        [self notifyStateDidChange];
        if (autoSaveDirectoryURL == nil) {
            [self scheduleFallbackDownloadFinalizeForIdentifier:identifierKey];
        }
    });
    return YES;
}

- (void)updateDownloadItem:(cef_download_item_t *)downloadItem
                  callback:(cef_download_item_callback_t *)callback {
    if (downloadItem == nullptr) {
        return;
    }

    uint32_t downloadIdentifier = downloadItem->get_id != nullptr ? downloadItem->get_id(downloadItem) : 0;
    NSNumber *identifierKey = @(downloadIdentifier);
    BOOL isComplete = downloadItem->is_complete != nullptr ? downloadItem->is_complete(downloadItem) != 0 : NO;
    BOOL isCanceled = downloadItem->is_canceled != nullptr ? downloadItem->is_canceled(downloadItem) != 0 : NO;
    BOOL isInterrupted = downloadItem->is_interrupted != nullptr ? downloadItem->is_interrupted(downloadItem) != 0 : NO;
    BOOL isInProgress = downloadItem->is_in_progress != nullptr ? downloadItem->is_in_progress(downloadItem) != 0 : NO;

    NSDictionary<NSString *, id> *downloadState = nil;
    @synchronized(self) {
        downloadState = self->_downloadStatesByIdentifier[identifierKey];
        if (isComplete || isCanceled || isInterrupted) {
            [self->_downloadStatesByIdentifier removeObjectForKey:identifierKey];
        }
    }

    NSString *suggestedFilename = [downloadState[@"suggestedFilename"] isKindOfClass:[NSString class]]
        ? downloadState[@"suggestedFilename"]
        : (downloadItem->get_suggested_file_name != nullptr
            ? CMUXCEFStringToNSString(downloadItem->get_suggested_file_name(downloadItem))
            : @"download");
    NSURL *tempURL = [downloadState[@"tempURL"] isKindOfClass:[NSURL class]] ? downloadState[@"tempURL"] : nil;
    NSURL *directSaveURL = [downloadState[@"directSaveURL"] isKindOfClass:[NSURL class]] ? downloadState[@"directSaveURL"] : nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger remainingDownloads = 0;
        @synchronized(self) {
            remainingDownloads = self->_downloadStatesByIdentifier.count;
        }
        self.isDownloading = remainingDownloads > 0;

        if (isInProgress) {
            [self notifyStateDidChange];
            return;
        }

        if (isCanceled || isInterrupted) {
            if (tempURL != nil) {
                [NSFileManager.defaultManager removeItemAtURL:tempURL error:nil];
            }
            self.runtimeStatusSummary = isCanceled ? @"Download canceled" : @"Download failed";
            [self updateStatusLabel];
            [self notifyStateDidChange];
            CMUXCEFDebugLog([NSString stringWithFormat:@"download.updated terminal id=%u state=%@",
                             downloadIdentifier,
                             isCanceled ? @"canceled" : @"interrupted"]);
            return;
        }

        if (!isComplete) {
            [self notifyStateDidChange];
            return;
        }

        if (directSaveURL != nil) {
            self.runtimeStatusSummary = [NSString stringWithFormat:@"Saved %@", directSaveURL.lastPathComponent ?: suggestedFilename];
            [self updateStatusLabel];
            [self notifyStateDidChange];
            CMUXCEFDebugLog([NSString stringWithFormat:@"download.updated complete id=%u dest=%@",
                             downloadIdentifier,
                             directSaveURL.path]);
            return;
        }

        if (tempURL == nil) {
            [self notifyStateDidChange];
            return;
        }

        CMUXCEFDebugLog([NSString stringWithFormat:@"download.updated complete id=%u temp=%@",
                         downloadIdentifier,
                         tempURL.path]);
        [self finalizeDownloadState:downloadState identifierKey:identifierKey suggestedName:suggestedFilename];
    });
}

- (void)scheduleFallbackDownloadFinalizeForIdentifier:(NSNumber *)identifierKey {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSDictionary<NSString *, id> *downloadState = nil;
        @synchronized(self) {
            downloadState = self->_downloadStatesByIdentifier[identifierKey];
        }
        if (downloadState == nil) {
            return;
        }

        NSURL *tempURL = [downloadState[@"tempURL"] isKindOfClass:[NSURL class]] ? downloadState[@"tempURL"] : nil;
        NSString *suggestedFilename = [downloadState[@"suggestedFilename"] isKindOfClass:[NSString class]]
            ? downloadState[@"suggestedFilename"]
            : @"download";
        NSInteger attempts = [downloadState[@"attempts"] respondsToSelector:@selector(integerValue)]
            ? [downloadState[@"attempts"] integerValue]
            : 0;
        long long lastObservedSize = [downloadState[@"lastObservedSize"] respondsToSelector:@selector(longLongValue)]
            ? [downloadState[@"lastObservedSize"] longLongValue]
            : -1;

        if (tempURL == nil) {
            @synchronized(self) {
                [self->_downloadStatesByIdentifier removeObjectForKey:identifierKey];
            }
            return;
        }

        NSNumber *fileSizeValue = nil;
        if ([tempURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:nil],
            fileSizeValue != nil,
            fileSizeValue.longLongValue >= 0) {
            long long fileSize = fileSizeValue.longLongValue;
            if (fileSize > 0 && fileSize == lastObservedSize) {
                CMUXCEFDebugLog([NSString stringWithFormat:@"download.fallback complete id=%@ temp=%@ size=%lld",
                                 identifierKey,
                                 tempURL.path,
                                 fileSize]);
                [self finalizeDownloadState:downloadState identifierKey:identifierKey suggestedName:suggestedFilename];
                return;
            }

            NSMutableDictionary<NSString *, id> *updatedState = [downloadState mutableCopy];
            updatedState[@"attempts"] = @(attempts + 1);
            updatedState[@"lastObservedSize"] = @(fileSize);
            @synchronized(self) {
                self->_downloadStatesByIdentifier[identifierKey] = updatedState;
            }
            if (attempts < 20) {
                [self scheduleFallbackDownloadFinalizeForIdentifier:identifierKey];
            }
            return;
        }

        if (attempts < 20) {
            NSMutableDictionary<NSString *, id> *updatedState = [downloadState mutableCopy];
            updatedState[@"attempts"] = @(attempts + 1);
            @synchronized(self) {
                self->_downloadStatesByIdentifier[identifierKey] = updatedState;
            }
            [self scheduleFallbackDownloadFinalizeForIdentifier:identifierKey];
        }
    });
}

- (void)finalizeDownloadState:(NSDictionary<NSString *, id> *)downloadState
                identifierKey:(NSNumber *)identifierKey
               suggestedName:(NSString *)suggestedFilename {
    NSDictionary<NSString *, id> *currentState = nil;
    @synchronized(self) {
        currentState = self->_downloadStatesByIdentifier[identifierKey];
        [self->_downloadStatesByIdentifier removeObjectForKey:identifierKey];
    }
    if (currentState == nil) {
        return;
    }

    NSURL *tempURL = [currentState[@"tempURL"] isKindOfClass:[NSURL class]] ? currentState[@"tempURL"] : nil;
    if (tempURL == nil) {
        return;
    }

    NSUInteger remainingDownloads = 0;
    @synchronized(self) {
        remainingDownloads = self->_downloadStatesByIdentifier.count;
    }
    self.isDownloading = remainingDownloads > 0;
    self.runtimeStatusSummary = [NSString stringWithFormat:@"Download ready %@", suggestedFilename];
    [self updateStatusLabel];
    [self notifyStateDidChange];

    if (NSURL *autoSaveDirectoryURL = CMUXCEFAutoSaveDownloadDirectoryURL()) {
        NSURL *destURL = [autoSaveDirectoryURL URLByAppendingPathComponent:suggestedFilename isDirectory:NO];
        NSError *moveError = nil;
        [NSFileManager.defaultManager removeItemAtURL:destURL error:nil];
        if (![NSFileManager.defaultManager moveItemAtURL:tempURL toURL:destURL error:&moveError]) {
            CMUXCEFDebugLog([NSString stringWithFormat:@"download.autoSave failed id=%@ error=%@",
                             identifierKey,
                             moveError.localizedDescription ?: @"unknown"]);
            [NSFileManager.defaultManager removeItemAtURL:tempURL error:nil];
        } else {
            self.runtimeStatusSummary = [NSString stringWithFormat:@"Saved %@", destURL.lastPathComponent ?: suggestedFilename];
            [self updateStatusLabel];
            [self notifyStateDidChange];
            CMUXCEFDebugLog([NSString stringWithFormat:@"download.autoSave success id=%@ dest=%@",
                             identifierKey,
                             destURL.path]);
        }
        return;
    }

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.nameFieldStringValue = suggestedFilename;
    savePanel.canCreateDirectories = YES;
    savePanel.directoryURL = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;

    void (^finish)(NSModalResponse) = ^(NSModalResponse result) {
        if (result != NSModalResponseOK || savePanel.URL == nil) {
            [NSFileManager.defaultManager removeItemAtURL:tempURL error:nil];
            return;
        }

        NSError *moveError = nil;
        [NSFileManager.defaultManager removeItemAtURL:savePanel.URL error:nil];
        if (![NSFileManager.defaultManager moveItemAtURL:tempURL toURL:savePanel.URL error:&moveError]) {
            CMUXCEFDebugLog([NSString stringWithFormat:@"download.save failed id=%@ error=%@",
                             identifierKey,
                             moveError.localizedDescription ?: @"unknown"]);
            [NSFileManager.defaultManager removeItemAtURL:tempURL error:nil];
            return;
        }

        self.runtimeStatusSummary = [NSString stringWithFormat:@"Saved %@", savePanel.URL.lastPathComponent ?: suggestedFilename];
        [self updateStatusLabel];
        [self notifyStateDidChange];
        CMUXCEFDebugLog([NSString stringWithFormat:@"download.save success id=%@ dest=%@",
                         identifierKey,
                         savePanel.URL.path]);
    };

    NSWindow *window = self->_browserView.window;
    if (window != nil) {
        [savePanel beginSheetModalForWindow:window completionHandler:finish];
    } else {
        [savePanel beginWithCompletionHandler:finish];
    }
}

- (void)addDocumentStartJavaScriptString:(NSString *)script {
    NSString *trimmed = [script stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return;
    }
    @synchronized(self) {
        if (![_documentStartScripts containsObject:trimmed]) {
            [_documentStartScripts addObject:trimmed];
        }
    }
}

- (void)executeJavaScriptString:(NSString *)script {
    NSString *trimmed = [script stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0 || _browser == nullptr || _browser->get_main_frame == nullptr) {
        return;
    }
    cef_frame_t *frame = _browser->get_main_frame(_browser);
    if (frame == nullptr || frame->execute_java_script == nullptr) {
        return;
    }
    cef_string_t source = CMUXCEFStringFromNSString(trimmed);
    cef_string_t scriptURL = CMUXCEFStringFromNSString(@"cmux://cef-bridge");
    frame->execute_java_script(frame, &source, &scriptURL, 1);
    CMUXCEFClearString(&source);
    CMUXCEFClearString(&scriptURL);
    CMUXCEFReleaseRefCounted(&frame->base);
}

- (void)reload {
    if (_browser != nullptr && _browser->reload != nullptr) {
        _browser->reload(_browser);
    }
}

- (void)stopLoading {
    if (_browser != nullptr && _browser->stop_load != nullptr) {
        _browser->stop_load(_browser);
    }
}

- (void)goBack {
    if (_browser != nullptr && _browser->go_back != nullptr) {
        _browser->go_back(_browser);
    }
}

- (void)goForward {
    if (_browser != nullptr && _browser->go_forward != nullptr) {
        _browser->go_forward(_browser);
    }
}

- (void)findText:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        [self clearFindResults];
        return;
    }
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->find == nullptr) {
        return;
    }

    BOOL continuingExistingSearch = findNext && [_activeFindQuery isEqualToString:trimmed] && _activeFindIdentifier > 0;
    if (!continuingExistingSearch) {
        _activeFindIdentifier += 1;
        _activeFindQuery = [trimmed copy];
    }

    cef_string_t query = CMUXCEFStringFromNSString(trimmed);
    host->find(host, _activeFindIdentifier, &query, forward ? 1 : 0, 0, continuingExistingSearch ? 1 : 0);
    CMUXCEFClearString(&query);
    CMUXCEFReleaseRefCounted(&host->base);
}

- (void)clearFindResults {
    _activeFindQuery = nil;
    _findMatchCount = 0;
    _selectedFindMatchOrdinal = 0;
    if (_browser != nullptr && _browser->get_host != nullptr) {
        cef_browser_host_t *host = _browser->get_host(_browser);
        if (host != nullptr) {
            if (host->stop_finding != nullptr) {
                host->stop_finding(host, 1);
            }
            CMUXCEFReleaseRefCounted(&host->base);
        }
    }
    [self notifyStateDidChange];
}

- (BOOL)zoomIn {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->get_zoom_level == nullptr || host->set_zoom_level == nullptr) {
        return NO;
    }
    double nextZoom = host->get_zoom_level(host) + 0.5;
    host->set_zoom_level(host, nextZoom);
    self.pageZoomFactor = CMUXCEFPageZoomForZoomLevel(nextZoom);
    CMUXCEFReleaseRefCounted(&host->base);
    return YES;
}

- (BOOL)zoomOut {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->get_zoom_level == nullptr || host->set_zoom_level == nullptr) {
        return NO;
    }
    double nextZoom = host->get_zoom_level(host) - 0.5;
    host->set_zoom_level(host, nextZoom);
    self.pageZoomFactor = CMUXCEFPageZoomForZoomLevel(nextZoom);
    CMUXCEFReleaseRefCounted(&host->base);
    return YES;
}

- (BOOL)resetZoom {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->set_zoom_level == nullptr) {
        return NO;
    }
    host->set_zoom_level(host, 0.0);
    self.pageZoomFactor = 1.0;
    CMUXCEFReleaseRefCounted(&host->base);
    return YES;
}

- (BOOL)applyPageZoomFactor:(double)pageZoomFactor {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->set_zoom_level == nullptr) {
        return NO;
    }
    double clamped = MAX(0.25, MIN(5.0, pageZoomFactor));
    double zoomLevel = CMUXCEFZoomLevelForPageZoom(clamped);
    host->set_zoom_level(host, zoomLevel);
    self.pageZoomFactor = CMUXCEFPageZoomForZoomLevel(zoomLevel);
    CMUXCEFReleaseRefCounted(&host->base);
    return YES;
}

- (BOOL)showDeveloperTools {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->show_dev_tools == nullptr) {
        return NO;
    }
    cef_window_info_t windowInfo = {};
    windowInfo.size = sizeof(windowInfo);
    cef_browser_settings_t browserSettings = {};
    browserSettings.size = sizeof(browserSettings);
    host->show_dev_tools(host, &windowInfo, &_client->client, &browserSettings, nullptr);
    CMUXCEFReleaseRefCounted(&host->base);
    return YES;
}

- (BOOL)hideDeveloperTools {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->close_dev_tools == nullptr) {
        return NO;
    }
    host->close_dev_tools(host);
    CMUXCEFReleaseRefCounted(&host->base);
    return YES;
}

- (BOOL)isDeveloperToolsVisible {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->has_dev_tools == nullptr) {
        return NO;
    }
    BOOL visible = host->has_dev_tools(host) != 0;
    CMUXCEFReleaseRefCounted(&host->base);
    return visible;
}

- (nullable NSArray<NSDictionary *> *)cookieDictionariesWithTimeout:(NSTimeInterval)timeout
                                                  errorDescription:(NSString * _Nullable * _Nullable)errorDescription {
    if (_requestContext == nullptr || _requestContext->get_cookie_manager == nullptr) {
        if (errorDescription != nullptr) {
            *errorDescription = @"CEF cookie manager is unavailable";
        }
        return nil;
    }

    cef_cookie_manager_t *cookieManager = _requestContext->get_cookie_manager(_requestContext, nullptr);
    if (cookieManager == nullptr || cookieManager->visit_all_cookies == nullptr) {
        if (errorDescription != nullptr) {
            *errorDescription = @"CEF cookie manager is unavailable";
        }
        return nil;
    }

    CEFCookieVisitWaiter *waiter = [[CEFCookieVisitWaiter alloc] init];
    CMUXCEFCookieVisitorState *visitor = new CMUXCEFCookieVisitorState();
    visitor->refCount.store(1);
    visitor->waiter = waiter;
    visitor->nameFilter = nil;
    visitor->domainFilter = nil;
    visitor->deleteMatches = NO;
    visitor->visitor.base.size = sizeof(cef_cookie_visitor_t);
    visitor->visitor.base.add_ref = &CMUXCEFCookieVisitorAddRef;
    visitor->visitor.base.release = &CMUXCEFCookieVisitorRelease;
    visitor->visitor.base.has_one_ref = &CMUXCEFCookieVisitorHasOneRef;
    visitor->visitor.base.has_at_least_one_ref = &CMUXCEFCookieVisitorHasAtLeastOneRef;
    visitor->visitor.visit = &CMUXCEFCookieVisitorVisit;

    if (!cookieManager->visit_all_cookies(cookieManager, &visitor->visitor)) {
        CMUXCEFReleaseRefCounted(&visitor->visitor.base);
        CMUXCEFReleaseRefCounted(&cookieManager->base);
        if (errorDescription != nullptr) {
            *errorDescription = @"Failed to enumerate CEF cookies";
        }
        return nil;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(timeout, 0.1)];
    while (!waiter.completed && [deadline timeIntervalSinceNow] > 0) {
        if (!waiter.sawCookie && [[NSDate date] timeIntervalSinceDate:waiter.lastUpdateAt] > 0.15) {
            waiter.completed = YES;
            break;
        }
        (void)[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }

    CMUXCEFReleaseRefCounted(&visitor->visitor.base);
    CMUXCEFReleaseRefCounted(&cookieManager->base);

    if (!waiter.completed) {
        if (errorDescription != nullptr) {
            *errorDescription = @"Timed out reading CEF cookies";
        }
        return nil;
    }
    if (errorDescription != nullptr) {
        *errorDescription = waiter.errorDescription;
    }
    return [waiter.cookies copy];
}

- (BOOL)setCookieDictionaries:(NSArray<NSDictionary *> *)cookies
             fallbackURLString:(nullable NSString *)fallbackURLString
                       timeout:(NSTimeInterval)timeout
                         count:(NSUInteger *)count
              errorDescription:(NSString * _Nullable * _Nullable)errorDescription {
    if (count != nullptr) {
        *count = 0;
    }
    if (_requestContext == nullptr || _requestContext->get_cookie_manager == nullptr) {
        if (errorDescription != nullptr) {
            *errorDescription = @"CEF cookie manager is unavailable";
        }
        return NO;
    }

    cef_cookie_manager_t *cookieManager = _requestContext->get_cookie_manager(_requestContext, nullptr);
    if (cookieManager == nullptr || cookieManager->set_cookie == nullptr) {
        if (errorDescription != nullptr) {
            *errorDescription = @"CEF cookie manager is unavailable";
        }
        return NO;
    }

    NSUInteger setCount = 0;
    for (NSDictionary *raw in cookies) {
        if (![raw isKindOfClass:[NSDictionary class]]) {
            if (errorDescription != nullptr) {
                *errorDescription = @"Invalid cookie payload";
            }
            CMUXCEFReleaseRefCounted(&cookieManager->base);
            return NO;
        }

        NSString *urlString = CMUXCEFURLStringForCookieDictionary(raw, fallbackURLString);
        cef_cookie_t cookie = {};
        if (urlString.length == 0 || !CMUXCEFPopulateCookie(&cookie, raw, fallbackURLString)) {
            if (errorDescription != nullptr) {
                *errorDescription = @"Invalid cookie payload";
            }
            CMUXCEFReleaseRefCounted(&cookieManager->base);
            return NO;
        }

        CEFCookieWriteWaiter *waiter = [[CEFCookieWriteWaiter alloc] init];
        CMUXCEFSetCookieCallbackState *callbackState = new CMUXCEFSetCookieCallbackState();
        callbackState->refCount.store(1);
        callbackState->waiter = waiter;
        callbackState->callback.base.size = sizeof(cef_set_cookie_callback_t);
        callbackState->callback.base.add_ref = &CMUXCEFSetCookieCallbackAddRef;
        callbackState->callback.base.release = &CMUXCEFSetCookieCallbackRelease;
        callbackState->callback.base.has_one_ref = &CMUXCEFSetCookieCallbackHasOneRef;
        callbackState->callback.base.has_at_least_one_ref = &CMUXCEFSetCookieCallbackHasAtLeastOneRef;
        callbackState->callback.on_complete = &CMUXCEFSetCookieCallbackComplete;

        cef_string_t cefURL = CMUXCEFStringFromNSString(urlString);
        BOOL started = cookieManager->set_cookie(cookieManager, &cefURL, &cookie, &callbackState->callback) != 0;
        CMUXCEFClearString(&cefURL);
        CMUXCEFClearCookie(&cookie);
        if (!started) {
            CMUXCEFReleaseRefCounted(&callbackState->callback.base);
            CMUXCEFReleaseRefCounted(&cookieManager->base);
            if (errorDescription != nullptr) {
                *errorDescription = @"Failed to set CEF cookie";
            }
            return NO;
        }

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(timeout, 0.1)];
        while (!waiter.completed && [deadline timeIntervalSinceNow] > 0) {
            (void)[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        CMUXCEFReleaseRefCounted(&callbackState->callback.base);

        if (!waiter.completed || waiter.integerResult <= 0) {
            CMUXCEFReleaseRefCounted(&cookieManager->base);
            if (errorDescription != nullptr) {
                *errorDescription = waiter.errorDescription ?: @"Timed out setting CEF cookie";
            }
            return NO;
        }
        setCount += 1;
    }

    CMUXCEFReleaseRefCounted(&cookieManager->base);
    if (count != nullptr) {
        *count = setCount;
    }
    if (errorDescription != nullptr) {
        *errorDescription = nil;
    }
    return YES;
}

- (NSUInteger)clearCookiesMatchingName:(nullable NSString *)name
                                domain:(nullable NSString *)domain
                               timeout:(NSTimeInterval)timeout
                      errorDescription:(NSString * _Nullable * _Nullable)errorDescription {
    if (_requestContext == nullptr || _requestContext->get_cookie_manager == nullptr) {
        if (errorDescription != nullptr) {
            *errorDescription = @"CEF cookie manager is unavailable";
        }
        return NSNotFound;
    }

    cef_cookie_manager_t *cookieManager = _requestContext->get_cookie_manager(_requestContext, nullptr);
    if (cookieManager == nullptr || cookieManager->visit_all_cookies == nullptr) {
        if (errorDescription != nullptr) {
            *errorDescription = @"CEF cookie manager is unavailable";
        }
        return NSNotFound;
    }

    CEFCookieVisitWaiter *waiter = [[CEFCookieVisitWaiter alloc] init];
    CMUXCEFCookieVisitorState *visitor = new CMUXCEFCookieVisitorState();
    visitor->refCount.store(1);
    visitor->waiter = waiter;
    visitor->nameFilter = [name copy];
    visitor->domainFilter = [domain copy];
    visitor->deleteMatches = YES;
    visitor->visitor.base.size = sizeof(cef_cookie_visitor_t);
    visitor->visitor.base.add_ref = &CMUXCEFCookieVisitorAddRef;
    visitor->visitor.base.release = &CMUXCEFCookieVisitorRelease;
    visitor->visitor.base.has_one_ref = &CMUXCEFCookieVisitorHasOneRef;
    visitor->visitor.base.has_at_least_one_ref = &CMUXCEFCookieVisitorHasAtLeastOneRef;
    visitor->visitor.visit = &CMUXCEFCookieVisitorVisit;

    if (!cookieManager->visit_all_cookies(cookieManager, &visitor->visitor)) {
        CMUXCEFReleaseRefCounted(&visitor->visitor.base);
        CMUXCEFReleaseRefCounted(&cookieManager->base);
        if (errorDescription != nullptr) {
            *errorDescription = @"Failed to enumerate CEF cookies";
        }
        return NSNotFound;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(timeout, 0.1)];
    while (!waiter.completed && [deadline timeIntervalSinceNow] > 0) {
        if (!waiter.sawCookie && [[NSDate date] timeIntervalSinceDate:waiter.lastUpdateAt] > 0.15) {
            waiter.completed = YES;
            break;
        }
        (void)[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }

    CMUXCEFReleaseRefCounted(&visitor->visitor.base);
    CMUXCEFReleaseRefCounted(&cookieManager->base);

    if (!waiter.completed) {
        if (errorDescription != nullptr) {
            *errorDescription = @"Timed out clearing CEF cookies";
        }
        return NSNotFound;
    }
    if (errorDescription != nullptr) {
        *errorDescription = nil;
    }
    return waiter.cookies.count;
}

- (nullable id)runAutomationJavaScript:(NSString *)script
                                timeout:(NSTimeInterval)timeout
                                useEval:(BOOL)useEval
                       errorDescription:(NSString * _Nullable * _Nullable)errorDescription {
    NSString *trimmed = [script stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        if (errorDescription != nullptr) {
            *errorDescription = @"Missing JavaScript";
        }
        return nil;
    }
    if (_browser == nullptr || _browser->get_main_frame == nullptr) {
        if (errorDescription != nullptr) {
            *errorDescription = @"CEF browser is not ready";
        }
        return nil;
    }

    NSString *token = NSUUID.UUID.UUIDString.lowercaseString;
    CEFAutomationWaiter *waiter = [[CEFAutomationWaiter alloc] init];
    @synchronized(self) {
        _automationWaitersByToken[token] = waiter;
    }

    NSString *scriptLiteral = CMUXCEFJSONLiteral(trimmed);
    NSString *tokenLiteral = CMUXCEFJSONLiteral(token);

    NSString *executionBlock = useEval
        ? [NSString stringWithFormat:@"const __cmuxRaw = eval(%@);", scriptLiteral]
        : [NSString stringWithFormat:@"const __cmuxRaw = (%@);", trimmed];

    NSString *wrapped = [NSString stringWithFormat:
        @"(async () => {"
         "const __cmuxToken = %@;"
         "const __cmuxEncode = (payload) => {"
           "try { return btoa(unescape(encodeURIComponent(JSON.stringify(payload)))); }"
           "catch (error) {"
             "return btoa(unescape(encodeURIComponent(JSON.stringify({\"__cmux_t\":\"error\",\"error\":String((error&&error.message)||error||\"encode_failed\")}))));"
           "}"
         "};"
         "const __cmuxNormalize = (value, depth = 0) => {"
           "if (typeof value === 'undefined' || value === null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return value;"
           "if (depth >= 4) return String(value);"
           "if (Array.isArray(value)) return value.slice(0, 256).map((item) => __cmuxNormalize(item, depth + 1));"
           "if (typeof value === 'object') {"
             "const out = {};"
             "for (const [key, item] of Object.entries(value).slice(0, 256)) { out[key] = __cmuxNormalize(item, depth + 1); }"
             "return out;"
           "}"
           "return String(value);"
         "};"
         "const __cmuxMaybeAwait = async (value) => {"
           "if (value !== null && (typeof value === 'object' || typeof value === 'function') && typeof value.then === 'function') return await value;"
           "return value;"
         "};"
         "try {"
           "%@"
           "const __cmuxValue = await __cmuxMaybeAwait(__cmuxRaw);"
           "const __cmuxPayload = {\"__cmux_t\": (typeof __cmuxValue === 'undefined') ? 'undefined' : 'value', \"__cmux_v\": __cmuxNormalize(__cmuxValue)};"
           "console.log('__CMUX_EVAL__' + __cmuxToken + ':' + __cmuxEncode(__cmuxPayload));"
         "} catch (error) {"
           "const __cmuxError = {\"__cmux_t\":\"error\",\"error\":String((error&&error.message)||error||'JavaScript execution failed')};"
           "console.log('__CMUX_EVAL__' + __cmuxToken + ':' + __cmuxEncode(__cmuxError));"
         "}"
        "})();",
        tokenLiteral,
        executionBlock
    ];

    [self executeJavaScriptString:wrapped];

    NSTimeInterval timeoutSeconds = MAX(0.01, timeout);
    if (NSThread.isMainThread) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeoutSeconds];
        while (!waiter.completed) {
            if ([deadline timeIntervalSinceNow] <= 0) {
                break;
            }
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    } else {
        dispatch_time_t waitDeadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC));
        dispatch_semaphore_wait(waiter.semaphore, waitDeadline);
    }

    @synchronized(self) {
        [_automationWaitersByToken removeObjectForKey:token];
    }

    if (!waiter.completed) {
        if (errorDescription != nullptr) {
            *errorDescription = @"Timed out waiting for JavaScript result";
        }
        return nil;
    }
    if (waiter.errorDescription.length > 0) {
        if (errorDescription != nullptr) {
            *errorDescription = waiter.errorDescription;
        }
        return nil;
    }
    return waiter.resultValue;
}

- (void)handleLoadStartForFrame:(cef_frame_t *)frame {
    if (frame == nullptr || frame->execute_java_script == nullptr) {
        return;
    }
    if (frame->is_main != nullptr && !frame->is_main(frame)) {
        return;
    }

    NSArray<NSString *> *scripts = nil;
    @synchronized(self) {
        scripts = [_documentStartScripts copy];
    }
    if (scripts.count == 0) {
        return;
    }

    for (NSString *script in scripts) {
        NSString *trimmed = [script stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0) {
            continue;
        }
        cef_string_t source = CMUXCEFStringFromNSString(trimmed);
        cef_string_t scriptURL = CMUXCEFStringFromNSString(@"cmux://cef-document-start");
        frame->execute_java_script(frame, &source, &scriptURL, 1);
        CMUXCEFClearString(&source);
        CMUXCEFClearString(&scriptURL);
    }
}

- (void)containerViewDidMoveToWindow:(CEFBrowserContainerView *)view {
    CMUXCEFDebugLog([NSString stringWithFormat:@"containerViewDidMoveToWindow inWindow=%d frame=%.0fx%.0f",
                     view.window != nil ? 1 : 0,
                     NSWidth(view.bounds),
                     NSHeight(view.bounds)]);
    [self ensureBrowserCreatedIfNeeded];
}

- (void)containerViewDidLayout:(CEFBrowserContainerView *)view {
    CMUXCEFDebugLog([NSString stringWithFormat:@"containerViewDidLayout browser=%d requestContext=%d inWindow=%d frame=%.0fx%.0f",
                     _browser != nullptr ? 1 : 0,
                     _requestContext != nullptr ? 1 : 0,
                     view.window != nil ? 1 : 0,
                     NSWidth(view.bounds),
                     NSHeight(view.bounds)]);
    [self createRequestContextIfNeeded];
    [self ensureBrowserCreatedIfNeeded];
    for (NSView *child in view.subviews) {
        child.frame = view.bounds;
        child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }

    if (_browser != nullptr && _browser->get_host != nullptr) {
        cef_browser_host_t *host = _browser->get_host(_browser);
        if (host != nullptr) {
            if (host->was_resized != nullptr) {
                host->was_resized(host);
            }
            if (host->notify_screen_info_changed != nullptr) {
                host->notify_screen_info_changed(host);
            }
            CMUXCEFReleaseRefCounted(&host->base);
        }
    }
}

- (void)containerViewDidBecomeFirstResponder:(CEFBrowserContainerView *)view {
    self.isBrowserSurfaceFocused = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"browserDidBecomeFirstResponderWebView"
                                                        object:view];
    if (_browser != nullptr && _browser->get_host != nullptr) {
        cef_browser_host_t *host = _browser->get_host(_browser);
        if (host != nullptr && host->set_focus != nullptr) {
            host->set_focus(host, 1);
            CMUXCEFReleaseRefCounted(&host->base);
        }
    }
}

- (void)containerViewDidResignFirstResponder:(CEFBrowserContainerView *)view {
    self.isBrowserSurfaceFocused = NO;
    if (_browser != nullptr && _browser->get_host != nullptr) {
        cef_browser_host_t *host = _browser->get_host(_browser);
        if (host != nullptr && host->set_focus != nullptr) {
            host->set_focus(host, 0);
            CMUXCEFReleaseRefCounted(&host->base);
        }
    }
}

- (BOOL)focusBrowserSurface {
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return NO;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host == nullptr || host->set_focus == nullptr) {
        return NO;
    }
    self.isBrowserSurfaceFocused = YES;
    host->set_focus(host, 1);
    CMUXCEFReleaseRefCounted(&host->base);
    return YES;
}

- (void)unfocusBrowserSurface {
    self.isBrowserSurfaceFocused = NO;
    if (_browser == nullptr || _browser->get_host == nullptr) {
        return;
    }
    cef_browser_host_t *host = _browser->get_host(_browser);
    if (host != nullptr && host->set_focus != nullptr) {
        host->set_focus(host, 0);
        CMUXCEFReleaseRefCounted(&host->base);
    }
}

- (void)ensureBrowserCreatedIfNeeded {
    BOOL needsProxyIsolatedContext = self.socksProxyHost.length > 0 && self.socksProxyPort > 0;
    if (needsProxyIsolatedContext && (_requestContext == nullptr || !_requestContextInitialized)) {
        if (_browserView != nil) {
            CMUXCEFDebugLog([NSString stringWithFormat:@"createBrowserSync wait requestContextReady=%d requestContext=%d inWindow=%d frame=%.0fx%.0f",
                             _requestContextInitialized ? 1 : 0,
                             _requestContext != nullptr ? 1 : 0,
                             _browserView.window != nil ? 1 : 0,
                             NSWidth(_browserView.bounds),
                             NSHeight(_browserView.bounds)]);
        }
        return;
    }

    if (!_runtimeReady || _browserView == nil || _browser != nullptr || _browserView.window == nil) {
        if (_browserView != nil) {
            CMUXCEFDebugLog([NSString stringWithFormat:@"createBrowserSync skip runtimeReady=%d browserView=%d browser=%d inWindow=%d frame=%.0fx%.0f",
                             _runtimeReady ? 1 : 0,
                             _browserView != nil ? 1 : 0,
                             _browser != nullptr ? 1 : 0,
                             _browserView.window != nil ? 1 : 0,
                             NSWidth(_browserView.bounds),
                             NSHeight(_browserView.bounds)]);
        }
        return;
    }

    CMUXCEFDebugLog([NSString stringWithFormat:@"createBrowserSync begin url=%@ requestContext=%d frame=%.0fx%.0f",
                     self.currentURLString.length > 0 ? self.currentURLString : self.visibleURLString,
                     _requestContext != nullptr ? 1 : 0,
                     NSWidth(_browserView.bounds),
                     NSHeight(_browserView.bounds)]);

    cef_window_info_t windowInfo = {};
    windowInfo.size = sizeof(windowInfo);
    windowInfo.parent_view = (__bridge void *)_browserView;
    windowInfo.bounds.x = 0;
    windowInfo.bounds.y = 0;
    windowInfo.bounds.width = (int)NSWidth(_browserView.bounds);
    windowInfo.bounds.height = (int)NSHeight(_browserView.bounds);

    cef_browser_settings_t browserSettings = {};
    browserSettings.size = sizeof(browserSettings);
    cef_string_t initialURL = CMUXCEFStringFromNSString(self.currentURLString.length > 0 ? self.currentURLString : self.visibleURLString);
    cef_browser_t *browser = CEFGlobalRuntimeManager.sharedManager.browserCreateBrowserSyncFn(
        &windowInfo,
        &_client->client,
        &initialURL,
        &browserSettings,
        nullptr,
        _requestContext
    );
    CMUXCEFClearString(&initialURL);

    if (browser == nullptr) {
        CMUXCEFDebugLog(@"createBrowserSync failed browser=null");
        self.runtimeStatusSummary = @"CEF browser creation failed";
        [self updateStatusLabel];
        return;
    }

    CMUXCEFDebugLog(@"createBrowserSync returned browser");
    _browser = browser;
    self.runtimeStatusSummary = @"CEF browser attached";
    [self updateStatusLabel];
    [self containerViewDidLayout:_browserView];
}

- (void)createRequestContextIfNeeded {
    if (_requestContext != nullptr || !_runtimeReady) {
        return;
    }

    if (self.socksProxyHost.length == 0 || self.socksProxyPort <= 0) {
        CMUXCEFDebugLog(@"createRequestContext skipped no proxy");
        return;
    }

    CMUXCEFDebugLog([NSString stringWithFormat:@"createRequestContext begin proxy=%@:%d",
                     self.socksProxyHost,
                     self.socksProxyPort]);
    cef_request_context_settings_t settings = {};
    settings.size = sizeof(settings);
    // Keep workspace contexts in-memory for now. The current packaged CEF path
    // does not reliably create secondary on-disk Chrome profiles, but proxy
    // isolation still works with independent in-memory request contexts.
    settings.persist_session_cookies = 0;
    _requestContextInitialized = NO;
    if (_requestContextHandler == nullptr) {
        _requestContextHandler = CMUXCEFCreateRequestContextHandler(self);
    }
    _requestContext = CEFGlobalRuntimeManager.sharedManager.requestContextCreateContextFn(
        &settings,
        &_requestContextHandler->handler
    );

    if (_requestContext == nullptr) {
        CMUXCEFDebugLog(@"createRequestContext failed context=null");
        self.runtimeStatusSummary = @"CEF request context creation failed";
        if (_requestContextHandler != nullptr) {
            CMUXCEFReleaseRefCounted(&_requestContextHandler->handler.base);
            _requestContextHandler = nullptr;
        }
        return;
    }

    CMUXCEFDebugLog(@"createRequestContext returned context pending initialization");
    self.runtimeStatusSummary = @"CEF request context initializing";
    [self updateStatusLabel];
}

- (void)configureProxyPreferenceIfNeeded {
    if (_requestContext == nullptr || !_requestContextInitialized || self.socksProxyHost.length == 0 || self.socksProxyPort <= 0) {
        return;
    }

    NSString *server = [NSString stringWithFormat:@"socks5://%@:%d", self.socksProxyHost, self.socksProxyPort];
    __block NSString *firstError = nil;
    cef_dictionary_value_t *proxyDictionary = CEFGlobalRuntimeManager.sharedManager.dictionaryValueCreateFn();
    cef_value_t *proxyValue = CEFGlobalRuntimeManager.sharedManager.valueCreateFn();
    if (proxyDictionary != nullptr && proxyValue != nullptr) {
        cef_string_t modeKey = CMUXCEFStringFromNSString(@"mode");
        cef_string_t modeValue = CMUXCEFStringFromNSString(@"fixed_servers");
        cef_string_t serverKey = CMUXCEFStringFromNSString(@"server");
        cef_string_t serverValue = CMUXCEFStringFromNSString(server);
        cef_string_t bypassKey = CMUXCEFStringFromNSString(@"bypass_list");
        cef_string_t bypassValue = CMUXCEFStringFromNSString(@"<-loopback>");
        cef_string_t preferenceName = CMUXCEFStringFromNSString(@"proxy");
        cef_string_t error = {};

        proxyDictionary->set_string(proxyDictionary, &modeKey, &modeValue);
        proxyDictionary->set_string(proxyDictionary, &serverKey, &serverValue);
        proxyDictionary->set_string(proxyDictionary, &bypassKey, &bypassValue);
        proxyValue->set_dictionary(proxyValue, proxyDictionary);

        int didSetPreference = _requestContext->base.set_preference(
            &_requestContext->base,
            &preferenceName,
            proxyValue,
            &error
        );
        NSString *errorText = CMUXCEFStringToNSString(&error);
        CMUXCEFDebugLog([NSString stringWithFormat:@"requestContext setPreference name=proxy ok=%d value=%@ error=%@",
                         didSetPreference,
                         server,
                         errorText.length > 0 ? errorText : @""]);
        if (didSetPreference) {
            self.runtimeStatusSummary = [NSString stringWithFormat:@"CEF using SOCKS %@:%d", self.socksProxyHost, self.socksProxyPort];
            [self updateStatusLabel];

            CMUXCEFClearString(&error);
            CMUXCEFClearString(&modeKey);
            CMUXCEFClearString(&modeValue);
            CMUXCEFClearString(&serverKey);
            CMUXCEFClearString(&serverValue);
            CMUXCEFClearString(&bypassKey);
            CMUXCEFClearString(&bypassValue);
            CMUXCEFClearString(&preferenceName);
            // set_preference consumes |proxyValue| on success. Releasing it here
            // can double-release the nested dictionary after Chromium takes
            // ownership of the value tree.
            proxyDictionary = nullptr;
            proxyValue = nullptr;
            return;
        }

        if (firstError == nil) {
            firstError = errorText.length > 0 ? errorText : @"CEF proxy configuration failed";
        }

        CMUXCEFClearString(&error);
        CMUXCEFClearString(&modeKey);
        CMUXCEFClearString(&modeValue);
        CMUXCEFClearString(&serverKey);
        CMUXCEFClearString(&serverValue);
        CMUXCEFClearString(&bypassKey);
        CMUXCEFClearString(&bypassValue);
        CMUXCEFClearString(&preferenceName);
    }
    if (proxyDictionary != nullptr) {
        CMUXCEFReleaseRefCounted(&proxyDictionary->base);
    }
    if (proxyValue != nullptr) {
        CMUXCEFReleaseRefCounted(&proxyValue->base);
    }

    auto setStringPreference = ^BOOL(NSString *name, NSString *value) {
        cef_value_t *preferenceValue = CEFGlobalRuntimeManager.sharedManager.valueCreateFn();
        if (preferenceValue == nullptr || preferenceValue->set_string == nullptr) {
            if (firstError == nil) {
                firstError = @"CEF proxy preference value allocation failed";
            }
            if (preferenceValue != nullptr) {
                CMUXCEFReleaseRefCounted(&preferenceValue->base);
            }
            return NO;
        }

        cef_string_t preferenceName = CMUXCEFStringFromNSString(name);
        cef_string_t preferenceString = CMUXCEFStringFromNSString(value);
        cef_string_t error = {};
        preferenceValue->set_string(preferenceValue, &preferenceString);
        int didSetPreference = _requestContext->base.set_preference(
            &_requestContext->base,
            &preferenceName,
            preferenceValue,
            &error
        );
        NSString *errorText = CMUXCEFStringToNSString(&error);
        CMUXCEFDebugLog([NSString stringWithFormat:@"requestContext setPreference name=%@ ok=%d value=%@ error=%@",
                         name,
                         didSetPreference,
                         value,
                         errorText.length > 0 ? errorText : @""]);
        if (!didSetPreference && firstError == nil) {
            firstError = errorText.length > 0 ? errorText : [NSString stringWithFormat:@"CEF proxy preference %@ failed", name];
        }
        CMUXCEFClearString(&error);
        CMUXCEFClearString(&preferenceName);
        CMUXCEFClearString(&preferenceString);
        if (didSetPreference) {
            // set_preference consumes |preferenceValue| on success.
            preferenceValue = nullptr;
        }
        if (preferenceValue != nullptr) {
            CMUXCEFReleaseRefCounted(&preferenceValue->base);
        }
        return didSetPreference != 0;
    };

    BOOL didSetMode = setStringPreference(@"ProxyMode", @"fixed_servers");
    BOOL didSetServer = setStringPreference(@"ProxyServer", server);
    BOOL didSetBypass = setStringPreference(@"ProxyBypassList", @"<-loopback>");

    if (!(didSetMode && didSetServer && didSetBypass)) {
        self.runtimeStatusSummary = firstError ?: @"CEF proxy configuration failed";
    } else {
        self.runtimeStatusSummary = [NSString stringWithFormat:@"CEF using SOCKS %@:%d", self.socksProxyHost, self.socksProxyPort];
    }
    [self updateStatusLabel];
}

- (void)requestContextDidInitialize:(cef_request_context_t *)requestContext {
    if (requestContext == nullptr) {
        return;
    }
    BOOL replacedStoredContext = requestContext != _requestContext;
    if (replacedStoredContext) {
        requestContext->base.base.add_ref(&requestContext->base.base);
        if (_requestContext != nullptr) {
            CMUXCEFReleaseRefCounted(&_requestContext->base.base);
        }
        _requestContext = requestContext;
    }
    CMUXCEFDebugLog([NSString stringWithFormat:@"requestContext initialized requestContext=%p replacedStored=%d",
                     requestContext,
                     replacedStoredContext ? 1 : 0]);
    _requestContextInitialized = YES;
    [self configureProxyPreferenceIfNeeded];
    [self ensureBrowserCreatedIfNeeded];
}

- (void)tearDownBrowser {
    if (_browser != nullptr && _browser->get_host != nullptr) {
        cef_browser_host_t *host = _browser->get_host(_browser);
        if (host != nullptr && host->close_browser != nullptr) {
            host->close_browser(host, 1);
            CMUXCEFReleaseRefCounted(&host->base);
        }
        CMUXCEFReleaseRefCounted(&_browser->base);
        _browser = nullptr;
    }
    if (_requestContext != nullptr) {
        CMUXCEFReleaseRefCounted(&_requestContext->base.base);
        _requestContext = nullptr;
    }
    if (_requestContextHandler != nullptr) {
        CMUXCEFReleaseRefCounted(&_requestContextHandler->handler.base);
        _requestContextHandler = nullptr;
    }
    _requestContextInitialized = NO;
}

- (void)updateStatusLabel {
    if (_statusLabel == nil && _browserView != nil) {
        NSTextField *statusLabel = [NSTextField labelWithString:self.runtimeStatusSummary];
        statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
        statusLabel.alignment = NSTextAlignmentCenter;
        statusLabel.maximumNumberOfLines = 2;
        statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        statusLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
        statusLabel.textColor = NSColor.tertiaryLabelColor;
        [_browserView addSubview:statusLabel];
        [NSLayoutConstraint activateConstraints:@[
            [statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_browserView.leadingAnchor constant:12.0],
            [statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_browserView.trailingAnchor constant:-12.0],
            [statusLabel.bottomAnchor constraintEqualToAnchor:_browserView.bottomAnchor constant:-10.0],
            [statusLabel.centerXAnchor constraintEqualToAnchor:_browserView.centerXAnchor],
        ]];
        _statusLabel = statusLabel;
    }
    _statusLabel.stringValue = self.runtimeStatusSummary ?: @"";
}

- (void)notifyStateDidChange {
    if (self.stateDidChangeHandler == nil) {
        return;
    }
    self.stateDidChangeHandler();
}

- (void)requestOpenURLInNewTabString:(NSString *)urlString {
    if (urlString.length == 0 || self.openURLInNewTabHandler == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.openURLInNewTabHandler(urlString);
    });
}

- (void)resetFindState {
    _findMatchCount = 0;
    _selectedFindMatchOrdinal = 0;
}

- (void)updateFindResultsForIdentifier:(int)identifier
                                 count:(int)count
                    activeMatchOrdinal:(int)activeMatchOrdinal {
    if (identifier != _activeFindIdentifier) {
        return;
    }
    _findMatchCount = static_cast<NSUInteger>(MAX(count, 0));
    _selectedFindMatchOrdinal = static_cast<NSUInteger>(MAX(activeMatchOrdinal, 0));
}

- (void)handleAutomationConsoleMessage:(NSString *)message {
    static NSString * const prefix = @"__CMUX_EVAL__";
    if (![message hasPrefix:prefix]) {
        return;
    }

    NSString *payload = [message substringFromIndex:prefix.length];
    NSRange separatorRange = [payload rangeOfString:@":"];
    if (separatorRange.location == NSNotFound) {
        return;
    }

    NSString *token = [payload substringToIndex:separatorRange.location];
    NSString *encoded = [payload substringFromIndex:separatorRange.location + 1];
    NSData *base64Data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
    if (base64Data == nil) {
        return;
    }

    NSDictionary *decoded = [NSJSONSerialization JSONObjectWithData:base64Data options:0 error:nil];
    if (![decoded isKindOfClass:[NSDictionary class]]) {
        return;
    }

    CEFAutomationWaiter *waiter = nil;
    @synchronized(self) {
        waiter = _automationWaitersByToken[token];
    }
    if (waiter == nil || waiter.completed) {
        return;
    }

    NSString *type = decoded[@"__cmux_t"];
    if ([type isEqualToString:@"error"]) {
        waiter.errorDescription = [decoded[@"error"] isKindOfClass:[NSString class]]
            ? decoded[@"error"]
            : @"JavaScript execution failed";
    } else {
        waiter.resultValue = decoded;
    }
    waiter.completed = YES;
    dispatch_semaphore_signal(waiter.semaphore);
}

@end

static void CMUXCEFBridgeUpdateAddress(CEFWorkspaceBridge *bridge, NSString *url) {
    if (bridge == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        bridge.currentURLString = url.length > 0 ? url : bridge.currentURLString;
        [bridge notifyStateDidChange];
    });
}

static void CMUXCEFBridgeUpdateTitle(CEFWorkspaceBridge *bridge, NSString *title) {
    if (bridge == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        bridge.pageTitle = title.length > 0 ? title : @"CEF";
        [bridge notifyStateDidChange];
    });
}

static void CMUXCEFBridgeUpdateLoadingState(CEFWorkspaceBridge *bridge, BOOL isLoading, BOOL canGoBack, BOOL canGoForward) {
    if (bridge == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        bridge.isLoading = isLoading;
        bridge.canGoBack = canGoBack;
        bridge.canGoForward = canGoForward;
        if (isLoading) {
            [bridge resetFindState];
        }
        [bridge notifyStateDidChange];
    });
}

static double CMUXCEFZoomLevelForPageZoom(double pageZoomFactor) {
    double clamped = MAX(0.25, MIN(5.0, pageZoomFactor));
    return std::log(clamped) / std::log(1.2);
}

static double CMUXCEFPageZoomForZoomLevel(double zoomLevel) {
    double pageZoom = std::pow(1.2, zoomLevel);
    if (!std::isfinite(pageZoom)) {
        return 1.0;
    }
    return MAX(0.25, MIN(5.0, pageZoom));
}

static void CMUXCEFBridgeHandleLoadError(CEFWorkspaceBridge *bridge, NSInteger errorCode, NSString *errorText, NSString *failedURL) {
    if (bridge == nil) {
        return;
    }
    if (errorCode == CEF_ERR_ABORTED) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *title = NSLocalizedString(@"browser.error.cantOpen.title", nil);
        NSString *message = errorText.length > 0
            ? errorText
            : NSLocalizedString(@"browser.error.checkNetwork", nil);
        if (failedURL.length > 0) {
            title = NSLocalizedString(@"browser.error.cantReach.title", nil);
            NSString *messageFormat = NSLocalizedString(@"browser.error.cantReach.messageURL", nil);
            if (messageFormat.length > 0 && ![messageFormat isEqualToString:@"browser.error.cantReach.messageURL"]) {
                message = [NSString stringWithFormat:messageFormat, failedURL];
            }
            bridge.currentURLString = failedURL;
        }
        bridge.pageTitle = failedURL.length > 0 ? failedURL : title;
        bridge.runtimeStatusSummary = errorText.length > 0 ? errorText : title;
        NSString *escapedTitle = CMUXCEFEscapeHTML(title);
        NSString *escapedMessage = CMUXCEFEscapeHTML(message);
        NSString *escapedURL = CMUXCEFEscapeHTML(failedURL);
        NSString *reloadLabel = CMUXCEFEscapeHTML(NSLocalizedString(@"browser.error.reload", nil));
        NSString *retryURLLiteral = failedURL.length > 0 ? CMUXCEFJSONLiteral(failedURL) : @"null";
        NSString *html = [NSString stringWithFormat:
            @"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\">"
             "<style>"
             "body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;min-height:80vh;margin:0;padding:20px;background:#1a1a1a;color:#e0e0e0;}"
             ".container{text-align:center;max-width:420px;}"
             "h1{font-size:18px;font-weight:600;margin-bottom:8px;}"
             "p{font-size:13px;color:#999;line-height:1.5;}"
             ".url{font-size:12px;color:#666;word-break:break-all;margin-top:16px;}"
             "button{margin-top:20px;padding:6px 20px;background:#333;color:#e0e0e0;border:1px solid #555;border-radius:6px;font-size:13px;cursor:pointer;}"
             "button:hover{background:#444;}"
             "@media (prefers-color-scheme: light){body{background:#fafafa;color:#222;}p{color:#666;}.url{color:#999;}button{background:#eee;color:#222;border-color:#ccc;}button:hover{background:#ddd;}}"
             "</style>"
             "<script>"
             "const __cmuxRetryURL=%@;"
             "function cmuxRetry(){if(__cmuxRetryURL){window.location.replace(__cmuxRetryURL);}else{window.location.reload();}}"
             "</script>"
             "</head><body><div class=\"container\"><h1>%@</h1><p>%@</p><div class=\"url\">%@</div><button onclick=\"cmuxRetry()\">%@</button></div></body></html>",
            retryURLLiteral,
            escapedTitle,
            escapedMessage,
            escapedURL,
            reloadLabel
        ];
        NSString *dataURLString = CMUXCEFHTMLDataURLString(html);
        if (dataURLString.length > 0) {
            [bridge loadURLStringInMainFrame:dataURLString];
        }
        [bridge updateStatusLabel];
        [bridge notifyStateDidChange];
    });
}

static void CMUXCEFBridgeDidCreateBrowser(CEFWorkspaceBridge *bridge, cef_browser_t *browser) {
    if (bridge == nil || browser == nullptr) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        bridge.runtimeStatusSummary = @"CEF browser created";
        [bridge updateStatusLabel];
        [bridge notifyStateDidChange];
    });
}

static void CMUXCEFBridgeWillCloseBrowser(CEFWorkspaceBridge *bridge, cef_browser_t *browser) {
    if (bridge == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        bridge.runtimeStatusSummary = @"CEF browser closed";
        [bridge updateStatusLabel];
        [bridge notifyStateDidChange];
    });
}

static void CMUXCEFBridgeUpdateFindResults(CEFWorkspaceBridge *bridge, int identifier, int count, int activeMatchOrdinal, BOOL finalUpdate) {
    if (bridge == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [bridge updateFindResultsForIdentifier:identifier count:count activeMatchOrdinal:activeMatchOrdinal];
        [bridge notifyStateDidChange];
    });
}
