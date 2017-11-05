//
//  NSCursorAdditions.m
//  Alchemusica
//
//  Created by Toshi Nagata on Sun Nov 21 2004.
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

#import "NSCursorAdditions.h"

static NSCursor *sHorizontalMoveCursor;
static NSCursor *sVerticalMoveCursor;
static NSCursor *sHorizontalMovePlusCursor;
static NSCursor *sHorizontalMoveZoomCursor;
static NSCursor *sVerticalMovePlusCursor;
static NSCursor *sStretchCursor;
static NSCursor *sMoveAroundCursor;
static NSCursor *sLoupeCursor;
static NSCursor *sPencilCursor;
static NSCursor *sSpeakerCursor;

@implementation NSCursor (MyCursorAddition)

+ (NSCursor *)horizontalMoveCursor
{
    if (sHorizontalMoveCursor == nil)
        sHorizontalMoveCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"horizontal_move.png"] hotSpot: NSMakePoint(7, 7)];
    return sHorizontalMoveCursor;
}

+ (NSCursor *)verticalMoveCursor
{
    if (sVerticalMoveCursor == nil)
        sVerticalMoveCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"vertical_move.png"] hotSpot: NSMakePoint(7, 7)];
    return sVerticalMoveCursor;
}

+ (NSCursor *)horizontalMovePlusCursor
{
    if (sHorizontalMovePlusCursor == nil)
        sHorizontalMovePlusCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"horizontal_move_plus.png"] hotSpot: NSMakePoint(7, 7)];
    return sHorizontalMovePlusCursor;
}

+ (NSCursor *)horizontalMoveZoomCursor
{
    if (sHorizontalMoveZoomCursor == nil)
        sHorizontalMoveZoomCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"horizontal_move_zoom.png"] hotSpot: NSMakePoint(7, 6)];
    return sHorizontalMoveZoomCursor;
}

+ (NSCursor *)verticalMovePlusCursor
{
    if (sVerticalMovePlusCursor == nil)
        sVerticalMovePlusCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"vertical_move_plus.png"] hotSpot: NSMakePoint(7, 7)];
    return sVerticalMovePlusCursor;
}

+ (NSCursor *)stretchCursor
{
    if (sStretchCursor == nil)
        sStretchCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"stretch.png"] hotSpot: NSMakePoint(3, 7)];
    return sStretchCursor;
}

+ (NSCursor *)moveAroundCursor
{
    if (sMoveAroundCursor == nil)
        sMoveAroundCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"move_around.png"] hotSpot: NSMakePoint(7, 7)];
    return sMoveAroundCursor;
}

+ (NSCursor *)loupeCursor
{
    if (sLoupeCursor == nil)
        sLoupeCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"loupe.png"] hotSpot: NSMakePoint(6, 6)];
    return sLoupeCursor;
}

+ (NSCursor *)pencilCursor
{
    if (sPencilCursor == nil)
        sPencilCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"pencil_cursor.png"] hotSpot: NSMakePoint(4, 15)];
    return sPencilCursor;
}

+ (NSCursor *)speakerCursor
{
    if (sSpeakerCursor == nil)
        sSpeakerCursor = [[NSCursor alloc] initWithImage: [NSImage imageNamed: @"speaker_cursor.png"] hotSpot: NSMakePoint(8, 8)];
    return sSpeakerCursor;
}


@end
