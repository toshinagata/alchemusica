//
//  StripChartView.h
//  Created by Toshi Nagata on Sun Jan 26 2003.
//
/*
    Copyright (c) 2003-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <AppKit/AppKit.h>

#import <Cocoa/Cocoa.h>
#import "GraphicClientView.h"
#import "MDHeaders.h"

enum {
	kStripChartBarMode, kStripChartBoxMode
};

@interface StripChartView : GraphicClientView
{
	unsigned char mode;
	int eventKind, eventCode;
    int focusTrack;  //  -1: same as the piano roll, 0,1,...: track number
    MDCalibrator *calib;
    int stripDraggingMode;
	int lineShape;  // 0: no drawing, >0: drawing with line shapes defined as kGraphic****Shape (cf. GraphicWindowController.h)
    BOOL horizontal;
    NSPoint draggingStartPoint;
    NSPoint draggingPoint;
    NSRect selectionRect;
    NSRect limitRect;
}

- (void)setKindAndCode: (int32_t)kindAndCode;
- (int32_t)kindAndCode;

//  Dragging support (accompanying PianoRollView)
- (void)startExternalDraggingAtPoint:(NSPoint)aPoint mode:(int)aMode;
- (void)endExternalDragging;
- (void)setExternalDraggingPoint:(NSPoint)aPoint;

//  Interval of the horizontal grid lines (measured in chart values; also used in StripChartRulerView)
- (float)horizontalGridInterval;

//  Accessor methods for StripChartRulerView
//- (float)minValue;
//- (float)maxValue;

@end
