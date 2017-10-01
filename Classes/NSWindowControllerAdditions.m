//
//  NSWindowControllerAdditions.m
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

#import "NSWindowControllerAdditions.h"
//#import "TrackWindowController.h"
#import "ListWindowController.h"
#import "GraphicWindowController.h"

//NSString *gTrackWindowType = @"track window";
NSString *gGraphicWindowType = @"graphic window";
NSString *gListWindowType = @"list window";

NSLayoutManager *gSharedLayoutManager = nil;

@implementation NSWindowController (MyWindowControllerAddition)

+ (BOOL)canContainMultipleTracks
{
    return NO;
}

+ (Class)classForWindowType: (NSString *)windowType
{
    Class class;
//    if ([windowType isEqualToString: gTrackWindowType]) {
//        class = [TrackWindowController class];
//    } else
	if ([windowType isEqualToString: gGraphicWindowType]) {
        class = [GraphicWindowController class];
    } else if ([windowType isEqualToString: gListWindowType]) {
        class = [ListWindowController class];
    } else class = nil;
    return class;
}

- (NSMutableDictionary *)encodeWindow
{
    NSMutableDictionary *dict;
    dict = [NSMutableDictionary dictionary];
    [dict setObject: [self className] forKey: @"class name"];
    [dict setObject: [[self window] stringWithSavedFrame] forKey: @"frame"];
    return dict;
}

- (void)decodeWindowWithDictionary: (NSDictionary *)dictionary
{
    [[self window] setFrameFromString: [dictionary objectForKey: @"frame"]];
}

- (NSString *)windowType
{
    return @"";
}

- (BOOL)containsTrack: (int)trackNum
{
    return NO;
}

- (void)addTrack: (int)trackNum
{
}

- (void)setFocusFlag: (BOOL) flag onTrack: (int)trackNum extending: (BOOL)extendFlag
{
}

- (BOOL)isFocusTrack: (int)trackNum
{
	return NO;
}

- (void)reloadSelection
{
}

+ (NSLayoutManager *)sharedLayoutManager
{
    if (gSharedLayoutManager == nil) {
        gSharedLayoutManager = [[NSLayoutManager alloc] init];
    }
    return gSharedLayoutManager;
}

@end

@implementation NSWindowController (viewWithTag)

- (id)viewWithTag: (NSInteger)tag
{
	return [[[self window] contentView] viewWithTag: tag];
}

@end
