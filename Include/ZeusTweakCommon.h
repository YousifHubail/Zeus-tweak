/**
 * Shared preference helpers and cross-module exports.
 */
#ifndef ZeusTweakCommon_h
#define ZeusTweakCommon_h

#import <Foundation/Foundation.h>

#define ENABLED(setting) [[NSUserDefaults standardUserDefaults] boolForKey:[NSString stringWithFormat:@"%@_Enabled", setting]]

/** Implemented in HideFeedFiltering.m; chained from HideAds home feed adapter. */
NSArray *ZeusApplyHideFeedFiltering(NSArray *list, BOOL isMainFeed);

#endif
