//
//  GraphicClientView.m
//
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "GraphicClientView.h"
#import "GraphicWindowController.h"	//  for trackDuration
#import "MyDocument.h"
#import "NSCursorAdditions.h"

@implementation GraphicClientView

- (BOOL)hasVerticalScroller
{
	return YES;
}

+ (float)minHeight
{
	return 32.0;
}

- (int)clientViewType
{
	return kGraphicGenericViewType;
}

- (id)initWithFrame: (NSRect)rect
{
    self = [super initWithFrame: rect];
    if (self) {
        minValue = 0.0;
        maxValue = 128.0;
		dataSource = nil;
    }
    return self;
}

- (void)dealloc
{
	[dataSource release];
	[super dealloc];
}

- (void)setDataSource: (id)object
{
	if (dataSource != nil)
		[dataSource release];
	dataSource = [object retain];
}

- (id)dataSource
{
	return dataSource;
}

- (void)drawRect: (NSRect)aRect
{
}

- (void)paintEditingRange: (NSRect)aRect startX: (float *)startp endX: (float *)endp
{
	MDTickType startTick, endTick;
	float startx, endx;
	NSRect rect;
	float ppt = [dataSource pixelsPerTick];
	[(MyDocument *)[dataSource document] getEditingRangeStart: &startTick end: &endTick];
	if (startTick >= 0 && startTick < kMDMaxTick && endTick >= startTick) {
		startx = floor(startTick * ppt);
		endx = floor(endTick * ppt);
		rect = NSIntersectionRect(aRect, NSMakeRect(startx, aRect.origin.y, endx - startx, aRect.size.height));
		[[MyDocument colorForEditingRange] set];
		NSRectFillUsingOperation(rect, NSCompositeSourceAtop);
		[[NSColor blackColor] set];
	} else {
		startx = endx = -1;
	}
	if (startp != NULL)
		*startp = startx;
	if (endp != NULL)
		*endp = endx;
}

- (void)reloadData
{
	NSRect rect = [self frame];
	NSRect superRect = [[self superview] bounds];
	rect.size.width = [dataSource clientViewWidth];
//	rect.size.width = [dataSource sequenceDurationInQuarter] * [dataSource pixelsPerQuarter];
//	if (rect.size.width < superRect.size.width) {
	//	rect.size.width = superRect.size.width;
	//	NSLog(@"reloadData: want to adjust rect.size.width");
//	}
	if (![self hasVerticalScroller]) {
		rect.size.height = superRect.size.height;
	}
//	NSLog(@"reloadData for %@: %@", self, NSStringFromRect(rect));
//	if (yScale > 0 && maxValue > minValue)
//		rect.size.height = floor(yScale * (maxValue - minValue));
	[self setFrame: rect];
	[self setNeedsDisplay: YES];
}

- (void)setYScale: (float)y
{
    NSRect rect;
    if (maxValue > minValue) {
        rect = [self frame];
        rect.size.height = floor(y * (maxValue - minValue) + 0.5);
        [self setFrame: rect];
    }
}

- (float)yScale
{
    if (maxValue > minValue)
        return [self frame].size.height / (maxValue - minValue);
    else return 0.0;
}

- (void)setMinValue: (float)value
{
    minValue = value;
}

- (float)minValue
{
	return minValue;
}

- (void)setMaxValue: (float)value
{
    maxValue = value;
}

- (float)maxValue
{
	return maxValue;
}

- (void)addTrack: (int)track
{
}

- (void)removeTrack: (int)track
{
}

/*  Modify rectangle for redrawing selection region  */
- (NSRect)willInvalidateSelectRect: (NSRect)rect
{
    return rect;
}

- (void)invalidateSelectRegion
{
    NSRect rect;
    if (selectionPath != nil) {
        rect = [selectionPath bounds];
		rect = NSInsetRect(rect, -0.5, -0.5);
        rect = [self willInvalidateSelectRect: rect];
//        NSEraseRect(rect);
        rect = NSIntersectionRect(rect, [self visibleRect]);
        [self setNeedsDisplayInRect: rect];
    }
}

- (void)calcSelectRegion
{
    NSPoint pt1, pt2;
    NSRect rect;
    if (selectPoints != nil && [selectPoints count] > 1) {
        if (localGraphicTool == kGraphicRectangleSelectTool || localGraphicTool == kGraphicIbeamSelectTool || localGraphicTool == kGraphicPencilTool) {
            pt1 = [[selectPoints objectAtIndex: 0] pointValue];
            pt2 = [[selectPoints objectAtIndex: 1] pointValue];
            rect.origin = pt1;
            rect.size.width = pt2.x - pt1.x;
            if (rect.size.width < 0) {
                rect.size.width = -rect.size.width;
                rect.origin.x = pt2.x;
            }
			if (localGraphicTool == kGraphicRectangleSelectTool) {
				rect.size.height = pt2.y - pt1.y;
				if (rect.size.height < 0) {
					rect.size.height = -rect.size.height;
					rect.origin.y = pt2.y;
				}
			} else {
				NSRect bounds = [self bounds];
				rect.origin.y = bounds.origin.y - 1.0;
				rect.size.height = bounds.size.height + 2.0;
			}
			rect = NSInsetRect(rect, -0.5, -0.5);
            [selectionPath release];
            selectionPath = [[NSBezierPath bezierPathWithRect: rect] retain];
        }
    }
}

- (void)setSelectRegion: (NSBezierPath *)path
{
	[self invalidateSelectRegion];
	[selectionPath release];
	if (path == nil)
		selectionPath = nil;
	else {
		selectionPath = [path copyWithZone: [self zone]];
		[self invalidateSelectRegion];
	}
}

//- (int)selectMode
//{
//    return selectMode;
//}

- (BOOL)isDragging
{
    return isDragging;
}

//- (BOOL)shiftDown
//{
//    return shiftDown;
//}

- (NSArray *)selectPoints
{
    return selectPoints;
}

- (NSBezierPath *)selectionPath
{
    return selectionPath;
}

- (void)drawSelectRegion
{
    if (selectionPath != nil) {
		[[[MyDocument colorForSelectingRange] colorWithAlphaComponent: 0.1] set];
		[selectionPath fill];
        [[NSColor blackColor] set];
        [selectionPath stroke];
    }
}

- (BOOL)isPointInSelectRegion: (NSPoint)point
{
	if (selectionPath != nil)
		return [selectionPath containsPoint: point];
	else return NO;
}

- (void)autoscrollTimerCallback: (NSTimer *)timer
{
    NSEvent *event = (NSEvent *)[timer userInfo];
    [autoscrollTimer release];
    autoscrollTimer = nil;
    [self mouseDragged: event];
}

- (void)doMouseDown: (NSEvent *)theEvent
{
    if (initialModifierFlags & NSAlternateKeyMask) {
        [[NSCursor loupeCursor] set];
        isLoupeDragging = YES;
    } else {
        if ((initialModifierFlags & NSShiftKeyMask) == 0) {
            MyDocument *doc = [dataSource document];
			[doc unselectAllEventsInAllTracks: self];
            [self reloadData];
        }
    }
}

- (void)mouseDown: (NSEvent *)theEvent
{
    NSPoint pt;

	[dataSource mouseEvent:theEvent receivedByClientView:self];
    pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
	pt.x = [dataSource quantizedPixelFromPixel: pt.x];
    if (selectPoints == nil)
        selectPoints = [[NSMutableArray allocWithZone: [self zone]] init];
    else
        [selectPoints removeAllObjects];
    [selectPoints addObject: [NSValue valueWithPoint: pt]];
    initialModifierFlags = [theEvent modifierFlags];
    currentModifierFlags = initialModifierFlags;
    isDragging = isLoupeDragging = NO;
	localGraphicTool = [dataSource graphicTool];  // May be overridden in doMouseDown:
    [self doMouseDown: theEvent];
}

- (void)doMouseDragged: (NSEvent *)theEvent
{
    [self invalidateSelectRegion];
    [self calcSelectRegion];
    [self invalidateSelectRegion];
}

- (void)mouseDragged: (NSEvent *)theEvent
{
    NSPoint pt;
    NSRect bounds;
    NSValue *val;
	[dataSource mouseEvent:theEvent receivedByClientView:self];
    if (selectPoints == nil || [selectPoints count] == 0) {
        [super mouseDragged: theEvent];
		return;
	}
    if (autoscrollTimer != nil) {
        [autoscrollTimer invalidate];
        [autoscrollTimer release];
        autoscrollTimer = nil;
    }
    isDragging = YES;
    if ([self autoscroll: theEvent]) {
		float pos;
        autoscrollTimer = [[NSTimer scheduledTimerWithTimeInterval: 0.2 target: self selector:@selector(autoscrollTimerCallback:) userInfo: theEvent repeats: NO] retain];
		/*  Scroll position after autoscroll */
		pos = [[self superview] bounds].origin.x - [self frame].origin.x;
		/*  Scroll all the clientViews  */
		[(GraphicWindowController *)[self dataSource] scrollClientViewsToPosition: pos];
	}
    currentModifierFlags = [theEvent modifierFlags];
    pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
	pt.x = [dataSource quantizedPixelFromPixel: pt.x];
    bounds = [self bounds];
    if (pt.x < bounds.origin.x)
        pt.x = bounds.origin.x;
    if (pt.x > bounds.origin.x + bounds.size.width)
        pt.x = bounds.origin.x + bounds.size.width;
    if (pt.y < bounds.origin.y)
        pt.y = bounds.origin.y;
    if (pt.y > bounds.origin.y + bounds.size.height)
        pt.y = bounds.origin.y + bounds.size.height;
    val = [NSValue valueWithPoint: pt];
	/*  This is for linear (rectangle or ibeam) selection; also for pencil editing of strip chart */
	if (localGraphicTool == kGraphicRectangleSelectTool || localGraphicTool == kGraphicIbeamSelectTool || localGraphicTool == kGraphicPencilTool) {
		if ([selectPoints count] == 1)
			[selectPoints addObject: val];
		else
			[selectPoints replaceObjectAtIndex: 1 withObject: val];
	} else {
		/*  If marquee selection tool or free-hand pencil tool is to be implemented, 
		    the last point should be added to selectPoints here  */
	}
    [self doMouseDragged: theEvent];
    [self displayIfNeeded];
}

- (void)doZoomByOptionDrag: (NSEvent *)theEvent
{
    NSPoint pt1, pt2;
    NSRect visibleRect, documentRect;
    float pos, wid, r, oldppq;
    /*  Option + drag: zoom, Option + double click: unzoom  */
    switch ([theEvent clickCount]) {
        case 0: /* drag */
            pt1 = [[selectPoints objectAtIndex: 0] pointValue];
            pt2 = [[selectPoints objectAtIndex: 1] pointValue];
            visibleRect = [[self superview] bounds];
            documentRect = [self frame];
            if (pt1.x > pt2.x) {
                pos = pt2.x;
                wid = pt1.x - pt2.x;
            } else {
                pos = pt1.x;
                wid = pt2.x - pt1.x;
            }
            if (wid < 5)
                wid = 5;
            r = visibleRect.size.width / wid;
            if (r > 1) {
                oldppq = [dataSource pixelsPerQuarter];
				[dataSource zoomClientViewsWithPixelsPerQuarter:oldppq * r startingPos:pos * r];
            /*    [dataSource setPixelsPerQuarter: oldppq * r];
                [dataSource scrollClientViewsToPosition: pos * r];
				[dataSource reflectClientViews]; */
            }
            break;
        case 2: /* double-click */
			if ([theEvent modifierFlags] & NSShiftKeyMask)
				[dataSource rezoomClientViews];
			else [dataSource unzoomClientViews];
            break;
    }
    [[NSCursor arrowCursor] set];
}

- (void)doMouseUp: (NSEvent *)theEvent
{
    if (initialModifierFlags & NSAlternateKeyMask) {
        [self doZoomByOptionDrag: theEvent];
    }
}

- (void)mouseUp: (NSEvent *)theEvent
{
	[dataSource mouseEvent:theEvent receivedByClientView:self];

    if (selectPoints == nil || [selectPoints count] == 0) {
        [super mouseUp: theEvent];
		return;
	}
    if (autoscrollTimer != nil) {
        [autoscrollTimer invalidate];
        [autoscrollTimer release];
        autoscrollTimer = nil;
    }
    [self invalidateSelectRegion];
    currentModifierFlags = [theEvent modifierFlags];
    [self doMouseUp: theEvent];
    isDragging = isLoupeDragging = NO;
    [selectPoints removeAllObjects];
    [selectionPath release];
    selectionPath = nil;
    [self displayIfNeeded];
}

//- (void)draggingDidEnd: (NSRect)bounds
//{
//}

- (void)doMouseMoved: (NSEvent *)theEvent
{
    if ([theEvent modifierFlags] & NSAlternateKeyMask)
        [[NSCursor loupeCursor] set];
    else [[NSCursor arrowCursor] set];
}

- (void)doFlagsChanged: (NSEvent *)theEvent
{
    if ([theEvent modifierFlags] & NSAlternateKeyMask)
        [[NSCursor loupeCursor] set];
    else [[NSCursor arrowCursor] set];
}

@end
