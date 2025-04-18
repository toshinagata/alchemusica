//
//  GraphicClientView.m
//
/*
    Copyright (c) 2000-2025 Toshi Nagata. All rights reserved.

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
#import "PlayingViewController.h"   //  for getCurrentTick
#import "MyAppController.h"  //  for getOSXVersion

@implementation GraphicClientView

- (BOOL)hasVerticalScroller
{
	return YES;
}

+ (float)minHeight
{
	return 32.0f;
}

- (int)clientViewType
{
	return kGraphicGenericViewType;
}

- (id)initWithFrame: (NSRect)rect
{
    self = [super initWithFrame: rect];
    if (self) {
        minValue = 0.0f;
        maxValue = 128.0f;
		dataSource = nil;
		visibleRangeMin = 0.0f;
		visibleRangeMax = 1.0f;
		autoScaleOnResizing = YES;
        lastTimeIndicatorPos = -1.0;
    }
    return self;
}

- (void)dealloc
{
	[dataSource release];
	[super dealloc];
}

//  Respond when the scroll position changed
- (void)superBoundsDidChange: (NSNotification *)aNotification
{
}

//  Respond when the frame of the superview changed
//  i.e. the scroll view containing the client view is resized
- (void)superFrameDidChange: (NSNotification *)aNotification
{
}

//  Respond when the frame of the client view, i.e. data range and/or scale are changed
- (void)frameDidChange: (NSNotification *)aNotification
{
}

- (void)setDataSource: (id)object
{
	if (dataSource != nil)
		[dataSource release];
	dataSource = [object retain];

    //  Listen to notifications
    //  This should be somewhere after creation of GraphicClientView
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(superBoundsDidChange:)
     name: NSViewBoundsDidChangeNotification
     object: [self superview]];
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(superFrameDidChange:)
     name: NSViewFrameDidChangeNotification
     object: [self superview]];
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(frameDidChange:)
     name: NSViewFrameDidChangeNotification
     object: self];
}

- (id)dataSource
{
	return dataSource;
}

- (BOOL)isFocusTrack: (int)trackNum
{
    return [dataSource isFocusTrack:trackNum];
}
- (int32_t)visibleTrackCount
{
    return [dataSource visibleTrackCount];
}

- (int)sortedTrackNumberAtIndex: (int)index
{
    return [dataSource sortedTrackNumberAtIndex:index];
}

- (void)setFocusTrack:(int)aTrack
{
}

- (int)focusTrack
{
    return -1;
}

- (void)doTrackModified:(int)aTrack
{
}

CGFloat gLineDash1[] = {6.0f, 2.0f};
CGFloat gLineDash2[] = {2.0f, 6.0f};
CGFloat gDashWidth = 8.0f;

- (NSColor *)verticalLineColor: (BOOL)beforeEndOfSequence;
{
    if (beforeEndOfSequence)
        return [NSColor blackColor];
    else
        return [NSColor grayColor];
}

- (void)drawVerticalLinesInRect: (NSRect)aRect
{
    MDTickType beginTick, endTick, duration;
    float originTick, limitx;
    NSPoint pt1, pt2;
    int i, numLines;
    NSBezierPath *lines, *subLines;
    beginTick = [dataSource pixelToTick:aRect.origin.x];
    endTick = [dataSource pixelToTick:(aRect.origin.x + aRect.size.width)];
    duration = [dataSource sequenceDuration];
    limitx = [dataSource tickToPixel:duration];
    pt1.y = (CGFloat)(floor(aRect.origin.y / gDashWidth) * gDashWidth);
    pt2.y = (CGFloat)(ceil((aRect.origin.y + aRect.size.height) / gDashWidth) * gDashWidth);
    lines = [[NSBezierPath allocWithZone: [self zone]] init];
    subLines = [[NSBezierPath allocWithZone: [self zone]] init];
    originTick = beginTick;
    if (originTick == 0.0f)
        originTick = 1.0f;    /*  Avoid drawing line at tick = 0  */
    pt2.x = 0.0f;
    while (beginTick < endTick) {
        int mediumCount, majorCount;
        MDEvent *sig1, *sig2;
        MDTickType sigTick, nextSigTick;
        float interval, startTick;
        [dataSource verticalLinesFromTick: beginTick timeSignature: &sig1 nextTimeSignature: &sig2 lineInterval: &interval mediumCount: &mediumCount majorCount: &majorCount];
        sigTick = (sig1 == NULL ? 0 : MDGetTick(sig1));
        nextSigTick = (sig2 == NULL ? kMDMaxTick : MDGetTick(sig2));
        if (nextSigTick > endTick)
            nextSigTick = endTick;
        startTick = sigTick;
        numLines = (int)floor((nextSigTick - sigTick) / interval) + 1;
        i = (startTick >= originTick ? 0 : (int)floor((originTick - startTick) / interval));
        [[self verticalLineColor:true] set];
        for ( ; i < numLines; i++) {
            float pt1Tick = startTick + i * interval;
            if (pt1Tick >= originTick && pt1Tick <= endTick) {
                if (pt1Tick > duration && pt2.x <= limitx) {
                    /*  Draw the lines and set the color to gray  */
                    [lines setLineDash: gLineDash1 count: 2 phase: 0.0f];
                    [subLines setLineDash: gLineDash2 count: 2 phase: 0.0f];
                    [lines stroke];
                    [subLines stroke];
                    [lines removeAllPoints];
                    [subLines removeAllPoints];
                    [[self verticalLineColor:false] set];
                }
                pt1.x = (CGFloat)(floor([dataSource tickToPixel:pt1Tick]) + 0.5);
                pt2.x = pt1.x;
                if (i % majorCount == 0) {
                    [lines moveToPoint: pt1];
                    [lines lineToPoint: pt2];
                } else {
                    [subLines moveToPoint: pt1];
                    [subLines lineToPoint: pt2];
                }
            }
        }
        beginTick = nextSigTick;
    }
    [lines setLineDash: gLineDash1 count: 2 phase: 0.0f];
    [subLines setLineDash: gLineDash2 count: 2 phase: 0.0f];
    [lines stroke];
    [subLines stroke];
    [lines release];
    [subLines release];
    
    [[NSColor blackColor] set];
    if (limitx < aRect.origin.x + aRect.size.width) {
        /*  Draw the "end of sequence" line  */
        float width = [NSBezierPath defaultLineWidth];
        pt1.x = pt2.x = limitx;
        [NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
        [NSBezierPath setDefaultLineWidth: 2.0f];
        pt1.x = pt2.x += 3.0f;
        [NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
        [NSBezierPath setDefaultLineWidth: width];
    }
}

- (CGFloat)timeIndicatorLocationFromPos:(float)pos
{
    return floor([[self dataSource] tickToPixel:pos]) + 0.5;
}

- (CGFloat)timeIndicatorWidth
{
    return 3.0;
}

- (void)drawTimeIndicatorInRect: (NSRect)aRect
{
    float pos;
    NSPoint pt1, pt2;
    NSRect frame = [self frame];
    [self invalidateTimeIndicator];
    pos = [[self dataSource] timeIndicatorPos];
    if (pos >= 0) {
        pt1.x = [self timeIndicatorLocationFromPos:pos];
        pt1.y = frame.origin.y;
        pt2.x = pt1.x;
        pt2.y = pt1.y + frame.size.height;
        [[NSColor blackColor] set];
        [NSBezierPath strokeLineFromPoint:pt1 toPoint:pt2];
    }
    lastTimeIndicatorPos = pos;
    [self invalidateTimeIndicator];
}

- (void)invalidateTimeIndicator
{
    NSRect frame = [self frame];
    CGFloat wid = [self timeIndicatorWidth];
    NSRect rect = NSMakeRect(0.0, frame.origin.y, wid, frame.size.height);
    float pos;
    if (lastTimeIndicatorPos >= 0) {
        rect.origin.x = [self timeIndicatorLocationFromPos:lastTimeIndicatorPos] - wid * 0.5;
        [self setNeedsDisplayInRect:rect];
    }
    pos = [[self dataSource] timeIndicatorPos];
    if (pos >= 0) {
        rect.origin.x = [self timeIndicatorLocationFromPos:pos] - wid * 0.5;
        [self setNeedsDisplayInRect:rect];
    }
    pos = [[[self dataSource] playingViewController] getCurrentTick];
    if (pos >= 0) {
        rect.origin.x = [self timeIndicatorLocationFromPos:pos] - wid * 0.5;
        [self setNeedsDisplayInRect:rect];
    }
}

//  Should be overridden in subclasses
- (void)drawContentsInRect: (NSRect)aRect
{
}

- (void)drawRect: (NSRect)aRect
{
    [self drawContentsInRect:aRect];
    [self drawTimeIndicatorInRect:aRect];
}

- (void)paintEditingRange: (NSRect)aRect startX: (float *)startp endX: (float *)endp
{
	MDTickType startTick, endTick;
	float startx, endx;
	NSRect rect;
	[(MyDocument *)[dataSource document] getEditingRangeStart: &startTick end: &endTick];
	if (startTick >= 0 && startTick < kMDMaxTick && endTick >= startTick) {
        startx = floor([dataSource tickToPixel:startTick]);
        endx = floor([dataSource tickToPixel:endTick]);
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
        rect.size.height = (CGFloat)floor(y * (maxValue - minValue) + 0.5);
        [self setFrame: rect];
    }
}

- (float)yScale
{
	float ys;
    if (maxValue > minValue)
        ys = [self frame].size.height / (maxValue - minValue);
    else ys = 0.0f;
	return ys;
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

- (void)convertFromPoint:(NSPoint)pt toY:(float *)y andTick:(int32_t *)tick
{
	NSRect frame = [self frame];
	*y = (pt.y - frame.origin.y) * (maxValue - minValue) / frame.size.height + minValue;
    *tick = [dataSource pixelToTick:(pt.x - frame.origin.x)];
}

- (NSPoint)convertToPointFromY:(float)y andTick:(int32_t)tick
{
	NSPoint pt;
	NSRect frame = [self frame];
    pt.x = [dataSource tickToPixel:tick] + frame.origin.x;
	pt.y = (y - minValue) * frame.size.height / (maxValue - minValue) + frame.origin.y;
	return pt;
}

- (void)setVisibleRangeMin:(float)min max:(float)max
{
	visibleRangeMin = min;
	visibleRangeMax = max;
	[self restoreVisibleRange];
}

- (void)getVisibleRangeMin:(float *)min max:(float *)max
{
	[self saveVisibleRange];
	*min = visibleRangeMin;
	*max = visibleRangeMax;
}

- (void)saveVisibleRange
{
	NSRect frame = [self frame];
	NSRect clipBounds = [[self superview] bounds];
	visibleRangeMin = clipBounds.origin.y / frame.size.height;
	visibleRangeMax = (clipBounds.origin.y + clipBounds.size.height) / frame.size.height;
}

- (void)restoreVisibleRange
{
	NSRect clipBounds = [[self superview] bounds];
	NSRect frame = [self frame];
	frame.size.height = (CGFloat)floor(clipBounds.size.height / (visibleRangeMax - visibleRangeMin) + 0.5);
	[self setFrame:frame];
	clipBounds.origin.y = visibleRangeMin * frame.size.height;
	[self scrollPoint:clipBounds.origin];
}

/*
- (void)getScrollPositionWithRangeMin:(float *)rangeMin max:(float *)rangeMax
{
	NSRect frame = [self frame];
	NSRect clipBounds = [[self superview] bounds];
	*rangeMin = clipBounds.origin.y / frame.size.height;
	*rangeMax = (clipBounds.origin.y + clipBounds.size.height) / frame.size.height;
}

- (void)rescaleToShowRangeMin:(float)rangeMin max:(float)rangeMax
{
	NSRect clipBounds = [[self superview] bounds];
	NSRect frame = [self frame];
	frame.size.height = floor(clipBounds.size.height / (rangeMax - rangeMin) + 0.5);
	[self setFrame:frame];
	clipBounds.origin.y = rangeMin * frame.size.height;
	[self scrollPoint:clipBounds.origin];
}
*/

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
		rect = NSInsetRect(rect, -0.5f, -0.5f);
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
				rect.origin.y = bounds.origin.y - 1.0f;
				rect.size.height = bounds.size.height + 2.0f;
			}
			rect = NSInsetRect(rect, -0.5f, -0.5f);
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
		[[[MyDocument colorForSelectingRange] colorWithAlphaComponent: 0.1f] set];
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

- (NSString *)infoTextForMousePoint:(NSPoint)pt dragging:(BOOL)flag option:(int *)option
{
	MDTickType theTick;
	int32_t measure, beat, tick;
    if (option != NULL)
        *option = 0;
	theTick = [dataSource quantizedTickFromPixel:pt.x];
	[dataSource convertTick:theTick toMeasure:&measure beat:&beat andTick:&tick];
	return [NSString stringWithFormat:@"%d.%d.%d", measure, beat, tick];
}

- (int)modifyLocalGraphicTool:(int)originalGraphicTool
{
	return originalGraphicTool;
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
	localGraphicTool = [self modifyLocalGraphicTool:[dataSource graphicTool]];
    [self doMouseDown: theEvent];
    [dataSource updateCursorInfoForView:self atPosition:pt];
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
    [dataSource setInfoText:[self infoTextForMousePoint:pt dragging:YES option:NULL]];
    [dataSource updateCursorInfoForView:self atPosition:pt];
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
    NSRect visibleRect;
    float pos, wid, r, oldppq;
    /*  Option + drag: zoom, Option + double click: unzoom  */
    switch ([theEvent clickCount]) {
        case 0: /* drag */
            pt1 = [[selectPoints objectAtIndex: 0] pointValue];
            pt2 = [[selectPoints objectAtIndex: 1] pointValue];
            visibleRect = [[self superview] bounds];
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
    NSPoint pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
    pt.x = [dataSource quantizedPixelFromPixel: pt.x];
	[dataSource mouseEvent:theEvent receivedByClientView:self];
    [dataSource updateCursorInfoForView:self atPosition:pt];

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
	localGraphicTool = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
    if ([theEvent modifierFlags] & NSAlternateKeyMask)
        [[NSCursor loupeCursor] set];
    else if (localGraphicTool == kGraphicPencilTool)
		[[NSCursor pencilCursor] set];
	else if (localGraphicTool == kGraphicRectangleSelectTool)
		[[NSCursor crosshairCursor] set];
	else if (localGraphicTool == kGraphicIbeamSelectTool)
		[[NSCursor IBeamCursor] set];
	else [[NSCursor arrowCursor] set];
}

- (void)doFlagsChanged: (NSEvent *)theEvent
{
	localGraphicTool = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
    if ([theEvent modifierFlags] & NSAlternateKeyMask)
        [[NSCursor loupeCursor] set];
    else if (localGraphicTool == kGraphicPencilTool)
		[[NSCursor pencilCursor] set];
	else if (localGraphicTool == kGraphicRectangleSelectTool)
		[[NSCursor crosshairCursor] set];
	else if (localGraphicTool == kGraphicIbeamSelectTool)
		[[NSCursor IBeamCursor] set];
	else
		[[NSCursor arrowCursor] set];
}

- (float)scrollVerticalPosition
{
	NSRect visibleRect = [[self superview] bounds];
	return visibleRect.origin.y;
}

- (void)scrollToVerticalPosition:(float)pos
{
	NSRect visibleRect = [[self superview] bounds];
	NSRect documentRect = [self frame];
	float y1;
	y1 = documentRect.origin.y;
	if (pos < y1)
		pos = y1;
	y1 = documentRect.origin.y + documentRect.size.height - visibleRect.size.height;
	if (pos > y1)
		pos = y1;
	visibleRect.origin.y = pos;
	[self scrollPoint: visibleRect.origin];
	[self setNeedsDisplay:YES];
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	static int scroll_direction = 0;
	float dx, dy, newpos;

	if (scroll_direction == 0) {
		//  Scroll wheel behavior was changed in 10.7
		if ([(MyAppController *)[NSApp delegate] getOSXVersion] < 10700)
			scroll_direction = -1;
		else scroll_direction = 1;
	}
	
	dx = [theEvent deltaX];
	dy = [theEvent deltaY];
	if (dx != 0.0) {
		newpos = [[self dataSource] scrollPositionOfClientViews] - dx * (8 * scroll_direction);
		[[self dataSource] scrollClientViewsToPosition:newpos];
	}
	if (dy != 0.0) {
		//  Implement vertical scroll by ourselves
		newpos = [self scrollVerticalPosition] + dy * (4 * scroll_direction);
		[self scrollToVerticalPosition:newpos];
	}
}

- (void)viewWillStartLiveResize
{
	[self saveVisibleRange];
	[super viewWillStartLiveResize];
}

- (void)viewDidEndLiveResize
{
	if (autoScaleOnResizing)
		[self restoreVisibleRange];
	[super viewDidEndLiveResize];
}

@end
