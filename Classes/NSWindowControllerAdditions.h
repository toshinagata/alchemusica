//
//  NSWindowControllerAdditions.h
//
//  Created by Toshi Nagata on Mon Nov 08 2004.
//
/*
    Copyright (c) 2004-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

extern NSString *gTrackWindowType;
extern NSString *gGraphicWindowType;
extern NSString *gListWindowType;

@interface NSWindowController (MyWindowControllerAddition)
+ (BOOL)canContainMultipleTracks;
+ (Class)classForWindowType: (NSString *)windowType;
- (NSMutableDictionary *)encodeWindow;
- (void)decodeWindowWithDictionary: (NSDictionary *)dictionary;
- (NSString *)windowType;
- (BOOL)containsTrack: (int)trackNum;
- (void)addTrack: (int)trackNum;
- (void)setFocusFlag: (BOOL) flag onTrack: (int)trackNum extending: (BOOL)extendFlag;
- (BOOL)isFocusTrack: (int)trackNum;
- (void)reloadSelection;
+ (NSLayoutManager *)sharedLayoutManager;
@end

@interface NSWindowController (viewWithTag)
- (id)viewWithTag: (NSInteger)tag;
@end
