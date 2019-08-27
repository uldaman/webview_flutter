// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "JavaScriptChannelHandler.h"

@implementation FLTJavaScriptChannel {
  FlutterMethodChannel* _methodChannel;
  WKWebView* _webView;
}

- (instancetype)initWithMethodChannel:(FlutterMethodChannel*)methodChannel
                webView:(WKWebView*)webView {
  self = [super init];
  NSAssert(methodChannel != nil, @"methodChannel must not be null.");
  if (self) {
    _methodChannel = methodChannel;
    _webView = webView;
  }
  return self;
}

- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
  NSAssert(_methodChannel != nil, @"Can't send a message to an unitialized JavaScript channel.");
  NSDictionary* arguments = @{
    @"handler" : message.body[@"handler"],
    @"arguments" : message.body[@"args"]
  };
  __weak FLTJavaScriptChannel* weakSelf = self;
  [_methodChannel invokeMethod:@"javascriptChannelMessage" arguments:arguments result:^(FlutterResult _Nullable result) {
      if (result == FlutterMethodNotImplemented) {
        return;
      }
      FLTJavaScriptChannel* strongSelf = weakSelf;
      if ([result isKindOfClass:[FlutterError class]]) {
        [strongSelf->_webView evaluateJavaScript:[NSString stringWithFormat:@"window.flutter_webview_fail(%@, `%@`);", message.body[@"_postID"], [result message]] completionHandler:nil];
        return;
      }
      [strongSelf->_webView evaluateJavaScript:[NSString stringWithFormat:@"window.flutter_webview_succeed(%@, %@);", message.body[@"_postID"], result] completionHandler:nil];
  }];
}

@end
