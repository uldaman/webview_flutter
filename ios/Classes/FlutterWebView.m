// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FlutterWebView.h"
#import "FLTWKNavigationDelegate.h"
#import "JavaScriptChannelHandler.h"

@implementation FLTWebViewFactory {
  NSObject<FlutterBinaryMessenger>* _messenger;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  self = [super init];
  if (self) {
    _messenger = messenger;
  }
  return self;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
  return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
  FLTWebViewController* webviewController = [[FLTWebViewController alloc] initWithFrame:frame
                                                                         viewIdentifier:viewId
                                                                              arguments:args
                                                                        binaryMessenger:_messenger];
  return webviewController;
}

@end

@implementation FLTWebViewController {
  WKWebView* _webView;
  int64_t _viewId;
  FlutterMethodChannel* _channel;
  FLTWKNavigationDelegate* _navigationDelegate;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  if (self = [super init]) {
    _viewId = viewId;

    NSString* channelName = [NSString stringWithFormat:@"plugins.flutter.io/webview_%lld", viewId];
    _channel = [FlutterMethodChannel methodChannelWithName:channelName binaryMessenger:messenger];

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = [[WKUserContentController alloc] init];
    [self updateAutoMediaPlaybackPolicy:args[@"autoMediaPlaybackPolicy"]
                    inConfiguration:configuration];
    _webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];

    [self registerJavaScriptChannels:configuration.userContentController];
    NSString *injectJavascript = args[@"injectJavascript"];
    if (injectJavascript != (id)[NSNull null]) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:injectJavascript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
        [configuration.userContentController addUserScript:script];
    }

    _navigationDelegate = [[FLTWKNavigationDelegate alloc] initWithChannel:_channel];
    _webView.UIDelegate = _navigationDelegate;
    _webView.navigationDelegate = _navigationDelegate;

    [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
    [_webView addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:NULL];

    __weak __typeof__(self) weakSelf = self;
    [_channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
      [weakSelf onMethodCall:call result:result];
    }];
    NSDictionary<NSString*, id>* settings = args[@"settings"];
    [self applySettings:settings];
    // TODO(amirh): return an error if apply settings failed once it's possible to do so.
    // https://github.com/flutter/flutter/issues/36228

    NSString* initialUrl = args[@"initialUrl"];
    if ([initialUrl isKindOfClass:[NSString class]]) {
      [self loadUrl:initialUrl];
    }
  }
  return self;
}

- (UIView*)view {
  return _webView;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"] && object == _webView) {
        [_channel invokeMethod:@"onProgressChanged" arguments:@{@"progress": @(_webView.estimatedProgress)}];
    } else if ([keyPath isEqualToString:@"URL"] && object == _webView) {
        if (_webView.URL) {
            [_channel invokeMethod:@"onURLChanged" arguments:@{@"url" : _webView.URL.absoluteString}];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)onMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([[call method] isEqualToString:@"updateSettings"]) {
    [self onUpdateSettings:call result:result];
  } else if ([[call method] isEqualToString:@"loadUrl"]) {
    [self onLoadUrl:call result:result];
  } else if ([[call method] isEqualToString:@"canGoBack"]) {
    [self onCanGoBack:call result:result];
  } else if ([[call method] isEqualToString:@"canGoForward"]) {
    [self onCanGoForward:call result:result];
  } else if ([[call method] isEqualToString:@"goBack"]) {
    [self onGoBack:call result:result];
  } else if ([[call method] isEqualToString:@"goForward"]) {
    [self onGoForward:call result:result];
  } else if ([[call method] isEqualToString:@"reload"]) {
    [self onReload:call result:result];
  }  else if ([[call method] isEqualToString:@"stopLoading"]) {
    [self onStopLoading:call result:result];
  } else if ([[call method] isEqualToString:@"currentUrl"]) {
    [self onCurrentUrl:call result:result];
  } else if ([[call method] isEqualToString:@"loadHTMLString"]) {
    [self loadHTMLString:call result:result];
  } else if ([[call method] isEqualToString:@"evaluateJavascript"]) {
    [self onEvaluateJavaScript:call result:result];
  } else if ([[call method] isEqualToString:@"takeScreenshot"]) {
    [self onTakeScreenshot:call result:result];
  } else if ([[call method] isEqualToString:@"clearCache"]) {
    [self onClearCache:result];
  } else if ([[call method] isEqualToString:@"getTitle"]) {
    [self onGetTitle:result];
  } else if ([[call method] isEqualToString:@"resetUserScript"]) {
    [self onResetUserScript:call result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)onUpdateSettings:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* error = [self applySettings:[call arguments]];
  if (error == nil) {
    result(nil);
    return;
  }
  result([FlutterError errorWithCode:@"updateSettings_failed" message:error details:nil]);
}

- (void)onLoadUrl:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (![self loadRequest:[call arguments]]) {
    result([FlutterError
        errorWithCode:@"loadUrl_failed"
              message:@"Failed parsing the URL"
              details:[NSString stringWithFormat:@"Request was: '%@'", [call arguments]]]);
  } else {
    result(nil);
  }
}

- (void)onCanGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
  BOOL canGoBack = [_webView canGoBack];
  result([NSNumber numberWithBool:canGoBack]);
}

- (void)onCanGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
  BOOL canGoForward = [_webView canGoForward];
  result([NSNumber numberWithBool:canGoForward]);
}

- (void)onGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
  [_webView goBack];
  result(nil);
}

- (void)onGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
  [_webView goForward];
  result(nil);
}

- (void)onReload:(FlutterMethodCall*)call result:(FlutterResult)result {
  [_webView reload];
  result(nil);
}

- (void)onStopLoading:(FlutterMethodCall*)call result:(FlutterResult)result {
  [_webView stopLoading];
  result(nil);
}

- (void)onCurrentUrl:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (_webView.URL) {
    result([[_webView URL] absoluteString]);
  } else {
    result(@"");
  }
}

- (void)onTakeScreenshot:(FlutterMethodCall*)call result:(FlutterResult)result {
    [_webView takeSnapshotWithConfiguration:nil
                              completionHandler:^(UIImage * _Nullable snapshotImage, NSError * _Nullable error) {
                                  if (snapshotImage) {
                                    result(UIImagePNGRepresentation(snapshotImage));
                                  } else {
                                    result(nil);
                                  }
                              }];
}

- (void)onEvaluateJavaScript:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* jsString = [call arguments];
  if (!jsString) {
    result([FlutterError errorWithCode:@"evaluateJavaScript_failed"
                               message:@"JavaScript String cannot be null"
                               details:nil]);
    return;
  }
  NSString* jsWrapper = [NSString stringWithFormat:@"(function(){return JSON.stringify(eval(`%@`));})();", jsString];
  [_webView evaluateJavaScript:jsWrapper
             completionHandler:^(_Nullable id evaluateResult, NSError* _Nullable error) {
               if (error) {
                 result([FlutterError
                     errorWithCode:@"evaluateJavaScript_failed"
                           message:@"Failed evaluating JavaScript"
                           details:[NSString stringWithFormat:@"JavaScript string was: '%@'\n%@",
                                                              jsString, error]]);
               } else {
                 result([NSString stringWithFormat:@"%@", evaluateResult]);
               }
             }];
}

- (void)onClearCache:(FlutterResult)result {
  if (@available(iOS 9.0, *)) {
    NSSet* cacheDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
    WKWebsiteDataStore* dataStore = [WKWebsiteDataStore defaultDataStore];
    NSDate* dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
    [dataStore removeDataOfTypes:cacheDataTypes
                   modifiedSince:dateFrom
               completionHandler:^{
                 result(nil);
               }];
  } else {
    // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
    NSLog(@"Clearing cache is not supported for Flutter WebViews prior to iOS 9.");
  }
}

- (void)loadHTMLString:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSArray* arguments = [call arguments];
  if ([arguments[1] isKindOfClass:[NSString class]]) {
    [_webView loadHTMLString:arguments[0] baseURL:[NSURL URLWithString:arguments[1]]];
  } else {
    [_webView loadHTMLString:arguments[0] baseURL:nil];
  }
  result(nil);
}

-(void)dealloc {
    if (_webView != nil) {
        [_webView stopLoading];
        [_webView loadHTMLString:@"" baseURL:nil];
        [_webView setNavigationDelegate:nil];
        [_webView setUIDelegate:nil];
        [_webView.configuration.userContentController removeScriptMessageHandlerForName:@"flutter_webview"];
        [_webView.configuration.userContentController removeAllUserScripts];
        [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
        [_webView removeObserver:self forKeyPath:@"URL"];
        [_webView removeFromSuperview];
        _webView = nil;
        _channel = nil;
    }
}

- (void)onGetTitle:(FlutterResult)result {
  NSString* title = _webView.title;
  result(title);
}

- (void)onResetUserScript:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* injectJavascript = [call arguments];
  if (!injectJavascript) {
    result([FlutterError errorWithCode:@"resetUserScript_failed"
                               message:@"JavaScript String cannot be null"
                               details:nil]);
    return;
  }

  WKUserContentController* userContentController = _webView.configuration.userContentController;
  [userContentController removeScriptMessageHandlerForName:@"flutter_webview"];
  [userContentController removeAllUserScripts];

  [self registerJavaScriptChannels:userContentController];

  WKUserScript* script = [[WKUserScript alloc] initWithSource:injectJavascript injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
  [userContentController addUserScript:script];

  result(nil);
}

// Returns nil when successful, or an error message when one or more keys are unknown.
- (NSString*)applySettings:(NSDictionary<NSString*, id>*)settings {
  NSMutableArray<NSString*>* unknownKeys = [[NSMutableArray alloc] init];
  for (NSString* key in settings) {
    if ([key isEqualToString:@"jsMode"]) {
      NSNumber* mode = settings[key];
      [self updateJsMode:mode];
    } else if ([key isEqualToString:@"hasNavigationDelegate"]) {
      NSNumber* hasDartNavigationDelegate = settings[key];
      _navigationDelegate.hasDartNavigationDelegate = [hasDartNavigationDelegate boolValue];
    } else if ([key isEqualToString:@"debuggingEnabled"]) {
      // no-op debugging is always enabled on iOS.
    } else if ([key isEqualToString:@"userAgent"]) {
      NSString* userAgent = settings[key];
      [self updateUserAgent:[userAgent isEqual:[NSNull null]] ? nil : userAgent];
    } else {
      [unknownKeys addObject:key];
    }
  }
  if ([unknownKeys count] == 0) {
    return nil;
  }
  return [NSString stringWithFormat:@"webview_flutter: unknown setting keys: {%@}",
                                    [unknownKeys componentsJoinedByString:@", "]];
}

- (void)updateJsMode:(NSNumber*)mode {
  WKPreferences* preferences = [[_webView configuration] preferences];
  switch ([mode integerValue]) {
    case 0:  // disabled
      [preferences setJavaScriptEnabled:NO];
      break;
    case 1:  // unrestricted
      [preferences setJavaScriptEnabled:YES];
      break;
    default:
      NSLog(@"webview_flutter: unknown JavaScript mode: %@", mode);
  }
}

- (void)updateAutoMediaPlaybackPolicy:(NSNumber*)policy
                      inConfiguration:(WKWebViewConfiguration*)configuration {
  switch ([policy integerValue]) {
    case 0:  // require_user_action_for_all_media_types
      if (@available(iOS 10.0, *)) {
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
      } else {
        configuration.mediaPlaybackRequiresUserAction = true;
      }
      break;
    case 1:  // always_allow
      if (@available(iOS 10.0, *)) {
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
      } else {
        configuration.mediaPlaybackRequiresUserAction = false;
      }
      break;
    default:
      NSLog(@"webview_flutter: unknown auto media playback policy: %@", policy);
  }
}

- (bool)loadRequest:(NSDictionary<NSString*, id>*)request {
  if (!request) {
    return false;
  }

  NSString* url = request[@"url"];
  if ([url isKindOfClass:[NSString class]]) {
    id headers = request[@"headers"];
    if ([headers isKindOfClass:[NSDictionary class]]) {
      return [self loadUrl:url withHeaders:headers];
    } else {
      return [self loadUrl:url];
    }
  }

  return false;
}

- (bool)loadUrl:(NSString*)url {
  return [self loadUrl:url withHeaders:[NSMutableDictionary dictionary]];
}

- (bool)loadUrl:(NSString*)url withHeaders:(NSDictionary<NSString*, NSString*>*)headers {
  NSURL* nsUrl = [NSURL URLWithString:url];
  if (!nsUrl) {
    return false;
  }
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsUrl];
  [request setAllHTTPHeaderFields:headers];
  [_webView loadRequest:request];
  return true;
}

- (void)registerJavaScriptChannels:(WKUserContentController*)userContentController {
  FLTJavaScriptChannel* channel =
      [[FLTJavaScriptChannel alloc] initWithMethodChannel:_channel
                                                  webView:_webView];
  [userContentController addScriptMessageHandler:channel name:@"flutter_webview"];
  NSString* wrapperSource = @"(() => {"
      "var _callbacks = {};"
      "var _flutter_webview = webkit.messageHandlers.flutter_webview;"
      "var _f = (promise, postID, ...args) => {"
          "if (_callbacks.hasOwnProperty(postID)) {"
              "if (_callbacks[postID].hasOwnProperty(promise)) {"
                  "_callbacks[postID][promise](...args);"
              "};"
              "delete _callbacks[postID];"
          "};"
      "};"
      "Object.defineProperty(window, 'flutter_webview_succeed', {"
          "value: (postID, ...args) => {"
              "_f('resolve', postID, ...args);"
          "},"
          "writable: false"
      "});"
      "Object.defineProperty(window, 'flutter_webview_fail', {"
          "value: (postID, ...args) => {"
              "_f('reject', postID, ...args);"
          "},"
          "writable: false"
      "});"
      "Object.defineProperty(window, 'flutter_webview_post', {"
          "value: (handler, ...args) => {"
              "var _postID = setTimeout(() => { });"
              "_flutter_webview.postMessage({ 'handler': handler, '_postID': _postID, 'args': JSON.stringify(args) });"
              "return new Promise((resolve, reject) => {"
                  "_callbacks[_postID] = {};"
                  "_callbacks[_postID]['resolve'] = resolve;"
                  "_callbacks[_postID]['reject'] = reject;"
              "});"
          "},"
          "writable: false"
      "});"
  "})()";
  WKUserScript* wrapperScript =
      [[WKUserScript alloc] initWithSource:wrapperSource
                             injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                          forMainFrameOnly:YES];
  [userContentController addUserScript:wrapperScript];
}

- (void)updateUserAgent:(NSString*)userAgent {
  if (@available(iOS 9.0, *)) {
    [_webView setCustomUserAgent:userAgent];
  } else {
    NSLog(@"Updating UserAgent is not supported for Flutter WebViews prior to iOS 9.");
  }
}

@end
