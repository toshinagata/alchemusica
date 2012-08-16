//
//  GraphicClientView.h
//
/*
    Copyright (c) 2000-2012 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

enum {
	kGraphicGenericViewType = 0,
	kGraphicPianoRollViewType = 1,
	kGraphicTimeChartViewType = 2,
	kGraphicStripChartViewType = 3
};

@interface GraphicClientView : NSView {
    id dataSource;				//  The data source
    float minValue, maxValue;
    int localGraphicTool;     // Get value from -[GraphicWindowController graphicTool] in mouseDown handler and keep value. Some client (like TimeChartView) may want to override the selection mode.
    BOOL isDragging;
    BOOL isLoupeDragging;
    unsigned int initialModifierFlags;
    unsigned int currentModifierFlags;

    NSMutableArray *selectPoints;
    NSBezierPath *selectionPath;
	NSRect initialSelectionRect;
    NSTimer *autoscrollTimer;
}

//  Should be overridden in subclasses
+ (float)minHeight;
- (int)clientViewType;

- (BOOL)hasVerticalScroller;
- (void)setDataSource: (id)object;
- (id)dataSource;
- (void)paintEditingRange: (NSRect)aRect startX: (float *)startp endX: (float *)endp;
- (void)reloadData;
- (void)setYScale: (float)y;
- (float)yScale;
- (void)setMinValue: (float)value;
- (float)minValue;
- (void)setMaxValue: (float)value;
- (float)maxValue;
- (void)addTrack: (int)track;
- (void)removeTrack: (int)track;

//- (int)selectMode;
- (BOOL)isDragging;
//- (BOOL)shiftDown;
- (NSArray *)selectPoints;
- (NSBezierPath *)selectionPath;
- (NSRect)willInvalidateSelectRect: (NSRect)rect;
- (void)invalidateSelectRegion;
- (void)calcSelectRegion;
- (void)setSelectRegion: (NSBezierPath *)path;
- (void)drawSelectRegion;
- (BOOL)isPointInSelectRegion: (NSPoint)point;

//  The subclass should override this to respond to mouse actions
- (void)doMouseDown: (NSEvent *)theEvent;
- (void)doMouseDragged: (NSEvent *)theEvent;
- (void)doMouseUp: (NSEvent *)theEvent;
//- (void)draggingDidEnd: (NSRect)bounds;

//  Overrides for implementing selection rectangle/region
- (void)mouseDown: (NSEvent *)theEvent;
- (void)mouseDragged: (NSEvent *)theEvent;
- (void)mouseUp: (NSEvent *)theEvent;

//  Will be called from GraphicWindowController's mouseMoved: handler
- (void)doMouseMoved: (NSEvent *)theEvent;

//  Will be called from GraphicBackgroundView's flagsChanged: handler
- (void)doFlagsChanged: (NSEvent *)theEvent;

@end
