//
//    MDObjects.h
//
//    Created by Toshi Nagata on Mon Mar 04 2002.
//
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

#import <Cocoa/Cocoa.h>
#import "MDHeaders.h"

@interface MDEventObject : NSObject {
@public
	int32_t	position;
	MDEvent	event;
}
- (id)initWithMDEvent: (const MDEvent *)ep;
- (MDEvent *)eventPtr;
@end

@interface MDTrackObject : NSObject {
@public
	MDTrack	*track;
}
- (id)initWithMDTrack: (MDTrack *)inTrack;
- (MDTrack *)track;
@end

@interface IntGroupObject : NSObject {
@public
	IntGroup *pointSet;
}
- (id)initWithMDPointSet: (IntGroup *)inPointSet;
- (IntGroup *)pointSet;
@end

@interface MDSelectionObject : IntGroupObject {
@public
	MDTickType startTick, endTick;
	MDTrack *track;  /*  For caching only  */
	BOOL isEndOfTrackSelected;
}
- (BOOL)getStartTick: (MDTickType *)startTickPtr andEndTick: (MDTickType *)endTickPtr withMDTrack: (MDTrack *)inTrack;
@end

@interface MDTickRangeObject: NSObject {
@public
	MDTickType startTick, endTick;
}
- (id)initWithStartTick: (MDTickType)tick1 endTick: (MDTickType)tick2;
@end

/*  Create an NSMenu with CC names. Each menu item will have the target and action,
    and the control change number can be accessed by [sender tag] - tagOffset.  */
NSMenu *MDMenuWithControlNames(id target, SEL action, int tagOffset);

/*  Create an NSMenu with meta-event names. Each menu item will have the target and action,
    and the SMF meta number can be accessed by [sender tag] - tagOffset.  */
NSMenu *MDMenuWithMetaNames(id target, SEL action, int tagOffset);
