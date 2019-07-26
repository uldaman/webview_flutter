// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "JavaScriptChannelHandler.h"

@implementation FLTJavaScriptChannel {
  FlutterMethodChannel* _methodChannel;
  NSString* _javaScriptChannelName;
  WKWebView* _webView;
}

- (instancetype)initWithMethodChannel:(FlutterMethodChannel*)methodChannel
                javaScriptChannelName:(NSString*)javaScriptChannelName
                webView:(WKWebView*)webView {
  self = [super init];
  NSAssert(methodChannel != nil, @"methodChannel must not be null.");
  NSAssert(javaScriptChannelName != nil, @"javaScriptChannelName must not be null.");
  if (self) {
    _methodChannel = methodChannel;
    _javaScriptChannelName = javaScriptChannelName;
    _webView = webView;
  }
  return self;
}

- (void)userContentController:(WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
  NSAssert(_methodChannel != nil, @"Can't send a message to an unitialized JavaScript channel.");
  NSAssert(_javaScriptChannelName != nil,
           @"Can't send a message to an unitialized JavaScript channel.");
  NSDictionary* arguments = @{
    @"channel" : _javaScriptChannelName,
    @"message" : [NSString stringWithFormat:@"%@", message.body]
  };
  NSString* jsMethod = [NSString stringWithFormat:@"window.%@[%@]", _javaScriptChannelName, message.body[@"_callHandlerID"]];
  [_methodChannel invokeMethod:@"javascriptChannelMessage" arguments:arguments result:^(FlutterResult _Nullable result) {
      if (result == FlutterMethodNotImplemented) {
        return;
      }
      if ([result isKindOfClass:[FlutterError class]]) {
        [self->_webView evaluateJavaScript:[NSString stringWithFormat:@"%@['reject'](`%@`); delete %@;", jsMethod, [result message], jsMethod] completionHandler:nil];
        return;
      }
      [self->_webView evaluateJavaScript:[NSString stringWithFormat:@"%@['resolve'](%@); delete %@;", jsMethod, result, jsMethod] completionHandler:nil];
  }];
}

@end
