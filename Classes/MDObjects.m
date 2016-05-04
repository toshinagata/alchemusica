//
//  MDObjects.m
//
//  Created by Toshi Nagata on Mon Mar 04 2002.
/*
    Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "MDObjects.h"

@implementation MDEventObject

- (id)init
{
	self = [super init];
	position = 0;
	MDEventInit(&event);
	return self;
}

- (id)initWithMDEvent: (const MDEvent *)ep
{
	self = [super init];
	position = 0;
	if (ep != NULL)
		MDEventCopy(&event, ep, 1);
	else
		MDEventInit(&event);
	return self;
}

- (void)dealloc
{
	MDEventClear(&event);
	[super dealloc];
}

- (MDEvent *)eventPtr
{
	return &event;
}

@end

@implementation MDTrackObject

- (id)init
{
	self = [super init];
	track = MDTrackNew();
	if (track == NULL) {
		[self release];
		return nil;
	}
	return self;
}

- (id)initWithMDTrack: (MDTrack *)inTrack
{
	self = [super init];
	track = inTrack;
	MDTrackRetain(track);
	return self;
}

- (void)dealloc
{
	MDTrackRelease(track);
	[super dealloc];
}

- (MDTrack *)track
{
    return track;
}
@end

@implementation IntGroupObject

- (id)init
{
	self = [super init];
	pointSet = IntGroupNew();
	if (pointSet == NULL) {
		[self release];
		return nil;
	}
	return self;
}

- (id)initWithMDPointSet: (IntGroup *)inPointSet
{
	self = [super init];
	pointSet = inPointSet;
	IntGroupRetain(pointSet);
	return self;
}

- (void)dealloc
{
	IntGroupRelease(pointSet);
	[super dealloc];
}

- (IntGroup *)pointSet
{
    return pointSet;
}

@end

@implementation MDSelectionObject

- (id)init
{
	self = [super init];
	if (self != nil) {
		startTick = endTick = kMDNegativeTick;
		track = NULL;
	}
	return self;
}

- (id)initWithMDPointSet: (IntGroup *)inPointSet
{
	self = [super initWithMDPointSet: inPointSet];
	if (self != nil) {
		startTick = endTick = kMDNegativeTick;
		track = NULL;
		isEndOfTrackSelected = NO;
	}
	return self;
}

- (BOOL)getStartTick: (MDTickType *)startTickPtr andEndTick: (MDTickType *)endTickPtr withMDTrack: (MDTrack *)inTrack
{
	if (startTick < 0 || endTick < 0 || track != inTrack) {
		int idx = -1;
		MDEvent *ep;
		MDPointer *ptr = MDPointerNew(inTrack);
		if (ptr == NULL)
			return NO;
		startTick = endTick = kMDNegativeTick;
		while ((ep = MDPointerForwardWithPointSet(ptr, pointSet, &idx)) != NULL) {
			MDTickType tick1 = MDGetTick(ep);
			if (startTick < 0)
				startTick = endTick = tick1;
			if (MDHasDuration(ep)) {
				MDTickType tick2 = tick1 + MDGetDuration(ep);
				if (tick2 > endTick)
					endTick = tick2;
			} else if (tick1 > endTick) {
				endTick = tick1;
			}
		}
		MDPointerRelease(ptr);
		if (isEndOfTrackSelected) {
			MDTickType trackDuration = MDTrackGetDuration(inTrack);
			if (startTick == kMDNegativeTick)
				startTick = trackDuration;
			if (endTick < trackDuration)
				endTick = trackDuration;
		}
		if (startTick >= 0)
			track = inTrack;
		else track = NULL;
	}
	*startTickPtr = startTick;
	*endTickPtr = endTick;
	return YES;
}

@end

@implementation MDTickRangeObject

- (id)initWithStartTick: (MDTickType)tick1 endTick: (MDTickType)tick2
{
	self = [super init];
	if (self != nil) {
		startTick = tick1;
		endTick = tick2;
	}
	return self;
}

@end

static void
addControlNameToMenu(int code, NSMenu *menu, id target, SEL action, int tagOffset)
{
	MDEvent event;
	char name[64];
	NSMenuItem *item;
	MDEventInit(&event);
	MDSetKind(&event, kMDEventControl);
	MDSetCode(&event, (code & 0x7f));
	MDEventToKindString(&event, name, sizeof name);
	[menu addItemWithTitle: [NSString stringWithUTF8String: name + 1]  //  Chop the "*" at the top
		action: action keyEquivalent: @""];
	item = (NSMenuItem *)[menu itemAtIndex: [menu numberOfItems] - 1];
	[item setTag: (code & 0x7f) + tagOffset];
	[item setTarget: target];
}

NSMenu *
MDMenuWithControlNames(id target, SEL action, int tagOffset)
{
	static unsigned char sControlTopMenuCodes[] = { 1, 7, 10, 11, 64, 71, 72, 73, 74 };
	int i, j;
	NSMenu *submenu, *menu;
	menu = [[[NSMenu alloc] initWithTitle: @"Control names"] autorelease];
	for (i = 0; i < sizeof(sControlTopMenuCodes) / sizeof(sControlTopMenuCodes[0]); i++)
		addControlNameToMenu(sControlTopMenuCodes[i], menu, target, action, tagOffset);
	for (i = 0; i < 127; i++) {
		if (i % 32 == 0) {
			[menu addItemWithTitle: [NSString stringWithFormat: @"%d-%d", i, i + 31]
				action: nil keyEquivalent: @""];
			submenu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
			[[menu itemAtIndex: [menu numberOfItems] - 1]
				setSubmenu: submenu];
		}
		for (j = sizeof(sControlTopMenuCodes) / sizeof(sControlTopMenuCodes[0]) - 1; j >= 0; j--) {
			if (i == sControlTopMenuCodes[j])
				break;
		}
		if (j < 0)
			addControlNameToMenu(i, submenu, target, action, tagOffset);
	}
	return menu;
}

static void
addMetaNameToMenu(int code, NSMenu *menu, id target, SEL action, int tagOffset)
{
	MDEvent event;
	char name[64];
	NSMenuItem *item;
	MDEventInit(&event);
	MDSetKind(&event, MDEventSMFMetaNumberToEventKind(code));
	MDSetCode(&event, code);
	MDEventToKindString(&event, name, sizeof name);
	[menu addItemWithTitle: [NSString stringWithUTF8String: name + 1]  //  Chop the "@" at the top
		action: action keyEquivalent: @""];
	item = (NSMenuItem *)[menu itemAtIndex: [menu numberOfItems] - 1];
	[item setTag: (code & 0x7f) + tagOffset];
	[item setTarget: target];
}

NSMenu *
MDMenuWithMetaNames(id target, SEL action, int tagOffset)
{
	static unsigned char sMetaTopMenuCodes[] = {
		kMDMetaTempo, kMDMetaSMPTE, kMDMetaTimeSignature, kMDMetaKey,
		kMDMetaLyric, kMDMetaMarker, kMDMetaCuePoint,
		kMDMetaPortNumber
	};
	int i, j;
	NSMenu *submenu, *menu;
	menu = [[[NSMenu alloc] initWithTitle: @"Meta event names"] autorelease];
	for (i = 0; i < sizeof(sMetaTopMenuCodes) / sizeof(sMetaTopMenuCodes[0]); i++)
		addMetaNameToMenu(sMetaTopMenuCodes[i], menu, target, action, tagOffset);
	for (i = 0; i < 127; i++) {
		if (i % 32 == 0) {
			[menu addItemWithTitle: [NSString stringWithFormat: @"%d-%d", i, i + 31]
				action: nil keyEquivalent: @""];
			submenu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
			[[menu itemAtIndex: [menu numberOfItems] - 1]
				setSubmenu: submenu];
		}
		for (j = sizeof(sMetaTopMenuCodes) / sizeof(sMetaTopMenuCodes[0]) - 1; j >= 0; j--) {
			if (i == sMetaTopMenuCodes[j])
				break;
		}
		if (j < 0)
			addMetaNameToMenu(i, submenu, target, action, tagOffset);
	}
	return menu;
}
