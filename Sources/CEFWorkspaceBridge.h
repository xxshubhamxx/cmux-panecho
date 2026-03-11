#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CEFWorkspaceBridgeStateDidChangeHandler)(void);
typedef void (^CEFWorkspaceBridgeOpenURLHandler)(NSString *urlString);

@protocol CMUXBrowserSurfaceFocusControlling <NSObject>
@property(nonatomic) BOOL cmuxAllowsFirstResponderAcquisition;
@property(nonatomic, readonly) BOOL cmuxAllowsFirstResponderAcquisitionEffective;
@property(nonatomic, readonly) NSInteger cmuxDebugPointerFocusAllowanceDepth;
- (void)cmuxBeginPointerFocusAllowance;
- (void)cmuxEndPointerFocusAllowance;
@end

@interface CEFWorkspaceBridge : NSObject

@property(nonatomic, readonly, copy) NSString *visibleURLString;
@property(nonatomic, readonly, copy) NSString *socksProxyHost;
@property(nonatomic, readonly) int32_t socksProxyPort;
@property(nonatomic, readonly, copy) NSString *cachePath;
@property(nonatomic, readonly, copy) NSString *currentURLString;
@property(nonatomic, readonly, copy) NSString *pageTitle;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
@property(nonatomic, readonly) BOOL isLoading;
@property(nonatomic, readonly) BOOL isDownloading;
@property(nonatomic, readonly) BOOL isBrowserSurfaceFocused;
@property(nonatomic, readonly) double pageZoomFactor;
@property(nonatomic, readonly) NSUInteger findMatchCount;
@property(nonatomic, readonly) NSUInteger selectedFindMatchOrdinal;
@property(nonatomic, readonly) BOOL runtimeReady;
@property(nonatomic, readonly, copy) NSString *runtimeStatusSummary;
@property(nonatomic, copy, nullable) CEFWorkspaceBridgeStateDidChangeHandler stateDidChangeHandler;
@property(nonatomic, copy, nullable) CEFWorkspaceBridgeOpenURLHandler openURLInNewTabHandler;

+ (BOOL)isRuntimeLinked;
+ (NSString *)runtimeStatusSummary;
+ (BOOL)ensureGlobalRuntimeWithFrameworkPath:(NSString *)frameworkPath
                               helperAppPath:(nullable NSString *)helperAppPath
                              mainBundlePath:(NSString *)mainBundlePath
                           runtimeCacheRootPath:(NSString *)runtimeCacheRootPath
                            errorDescription:(NSString * _Nullable * _Nullable)errorDescription;

- (instancetype)initWithVisibleURLString:(NSString *)visibleURLString
                          socksProxyHost:(NSString *)socksProxyHost
                          socksProxyPort:(int32_t)socksProxyPort
                               cachePath:(NSString *)cachePath
                           frameworkPath:(NSString *)frameworkPath
                           helperAppPath:(nullable NSString *)helperAppPath
                           mainBundlePath:(NSString *)mainBundlePath
                        runtimeCacheRootPath:(NSString *)runtimeCacheRootPath NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (NSView *)makeBrowserView;
- (BOOL)focusBrowserSurface;
- (void)unfocusBrowserSurface;
- (void)navigateToURLString:(NSString *)urlString;
- (void)addDocumentStartJavaScriptString:(NSString *)script;
- (void)executeJavaScriptString:(NSString *)script;
- (void)reload;
- (void)stopLoading;
- (void)goBack;
- (void)goForward;
- (void)findText:(NSString *)text forward:(BOOL)forward findNext:(BOOL)findNext;
- (void)clearFindResults;
- (BOOL)zoomIn;
- (BOOL)zoomOut;
- (BOOL)resetZoom;
- (BOOL)applyPageZoomFactor:(double)pageZoomFactor;
- (BOOL)showDeveloperTools;
- (BOOL)hideDeveloperTools;
- (BOOL)isDeveloperToolsVisible;
- (nullable NSArray<NSDictionary *> *)cookieDictionariesWithTimeout:(NSTimeInterval)timeout
                                                  errorDescription:(NSString * _Nullable * _Nullable)errorDescription;
- (BOOL)setCookieDictionaries:(NSArray<NSDictionary *> *)cookies
             fallbackURLString:(nullable NSString *)fallbackURLString
                       timeout:(NSTimeInterval)timeout
                         count:(NSUInteger *)count
              errorDescription:(NSString * _Nullable * _Nullable)errorDescription;
- (NSUInteger)clearCookiesMatchingName:(nullable NSString *)name
                                domain:(nullable NSString *)domain
                               timeout:(NSTimeInterval)timeout
                      errorDescription:(NSString * _Nullable * _Nullable)errorDescription;
- (nullable id)runAutomationJavaScript:(NSString *)script
                                timeout:(NSTimeInterval)timeout
                                useEval:(BOOL)useEval
                       errorDescription:(NSString * _Nullable * _Nullable)errorDescription;

@end

NS_ASSUME_NONNULL_END
