//
//  StripChartView.h
//  Created by Toshi Nagata on Sun Jan 26 2003.
//
/*
    Copyright (c) 2003-2011 Toshi Nagata. All rights reserved.

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
//	float minValue, maxValue;
    MDCalibrator *calib;
    int stripDraggingMode;
	int lineShape;  // 0: no drawing, >0: drawing with line shapes defined as kGraphic****Shape (cf. GraphicWindowController.h)
    BOOL horizontal;
    NSPoint draggingStartPoint;
    NSPoint draggingPoint;
    NSRect selectionRect;
    NSRect limitRect;
}

- (void)setKindAndCode: (long)kindAndCode;
- (long)kindAndCode;

//  Accessor methods for StripChartRulerView
//- (float)minValue;
//- (float)maxValue;

@end
