//
//  StripChartView.m
//  Created by Toshi Nagata on Sun Jan 26 2003.
//
/*
    Copyright (c) 2003-2017 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "StripChartView.h"
#import "GraphicSplitterView.h"
#import <math.h>
#import "GraphicWindowController.h"
#import "MyDocument.h"
#import "MyMIDISequence.h"
#import "MDObjects.h"
#import "NSEventAdditions.h"
#import "NSCursorAdditions.h"

/*  The constants to approximate a parabola with a cubic bezier curve  */
/*  The cubic bezier curve (0, 0)-(ALPHA, 0)-(1-BETA, 1-2*BETA)-(1,1) approximates
    a parabola y = x^2 in [0, 1].  */
/* #define ALPHA 0.377009
#define BETA  0.286601 */
static const float sParabolaPoints[] = {0, 0, 0.35f, 0, 0.7f, 0.4f, 1, 1, -1};
static const float sArcPoints[] = {0, 0, 0.15f, 0.6f, 0.33f, 1, 0.5f, 1, 0.67f, 1, 0.85f, 0.6f, 1, 0, -1};
static const float sSigmoidPoints[] = {0, 0, 0.45f, 0, 0.55f, 1, 1, 1, -1};

/*  The resolutions for pencil drawing  */
/*  New events are generated so that the time/tick/value intervals are no less than
    these values. */
static MDTimeType sTimeResolution = 5000;
static MDTickType sTickResolution = 1;
static float sValueResolution = 1.0f;

@implementation StripChartView

- (int)clientViewType
{
	return kGraphicStripChartViewType;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
		eventKind = 0;  /*  Undefined  */
		eventCode = 0;
		minValue = 0.0f;
		maxValue = 128.0f;
		calib = NULL;
		focusTrack = -1;
    }
    return self;
}

- (void)dealloc
{
	if (calib != NULL)
		MDCalibratorRelease(calib);
	[super dealloc];
}

/*
- (BOOL)hasVerticalScroller
{
	return NO;
}
*/

static float
getYValue(const MDEvent *ep, int eventKind)
{
	if (eventKind == kMDEventNote)
		return MDGetNoteOnVelocity(ep);
	else if (eventKind == kMDEventInternalNoteOff)
		return MDGetNoteOffVelocity(ep);
	else if (eventKind == kMDEventTempo)
		return MDGetTempo(ep);
	else return MDGetData1(ep);
}

- (void)drawVelocityInRect: (NSRect)aRect
{
	float ppt, height;
	MDTickType beginTick, endTick;
	int32_t n;
	float dx, dy;
	NSBezierPath *draggingPath;
	NSMutableArray *array;
	height = [self bounds].size.height;
	ppt = [dataSource pixelsPerTick];
	beginTick = (MDTickType)floor(aRect.origin.x / ppt);
	endTick = (MDTickType)ceil((aRect.origin.x + aRect.size.width) / ppt);
	draggingPath = nil;
	array = nil;
	if (stripDraggingMode > 0) {
		dx = draggingPoint.x - draggingStartPoint.x;
		dy = draggingPoint.y - draggingStartPoint.y;
		if (dx < -0.5 || dx > 0.5 || dy < -0.5 || dy > 0.5) {
			array = [NSMutableArray array];
		}
		beginTick = (MDTickType)floor((aRect.origin.x - (dx > 0 ? dx : -dx)) / ppt);
		endTick = (MDTickType)ceil((aRect.origin.x + aRect.size.width + (dx > 0 ? dx : -dx)) / ppt);
	}
	for (n = [self visibleTrackCount] - 1; n >= 0; n--) {
		float x, y, ybase;
		MDEvent *ep;
		MDPointer *pt;
		NSColor *color;
		MDTrack *track;
		int32_t trackNo;
		trackNo = [self sortedTrackNumberAtIndex: n];
		track = [[[dataSource document] myMIDISequence] getTrackAtIndex: trackNo];
		if (track == NULL)
			continue;
		color = [[dataSource document] colorForTrack: trackNo enabled: [self isFocusTrack: trackNo]];
		[color set];
		pt = MDPointerNew(track);
		if (pt == NULL)
			break;
		MDPointerJumpToTick(pt, beginTick);
		MDPointerBackward(pt);
		ybase = aRect.origin.y - 1;
		while ((ep = MDPointerForward(pt)) != NULL && MDGetTick(ep) < endTick) {
			if (MDGetKind(ep) != kMDEventNote)
				continue;
			y = (float)(ceil((getYValue(ep, eventKind) - minValue) / (maxValue - minValue) * height) - 0.5);
			x = (float)(floor(MDGetTick(ep) * ppt) + 0.5);
			if (y >= aRect.origin.y) {
				if ([[dataSource document] isSelectedAtPosition: MDPointerGetPosition(pt) inTrack: trackNo]) {
					NSFrameRect(NSMakeRect(x - 1, y - 1, 3, 3));
					if (array != nil) {
						if (draggingPath == nil)
							draggingPath = [NSBezierPath bezierPath];
						[draggingPath appendBezierPathWithRect: NSMakeRect(x + dx - 1, y + dy - 1, 3, 3)];
						[draggingPath moveToPoint: NSMakePoint(x + dx, y + dy)];
						[draggingPath lineToPoint: NSMakePoint(x + dx, ybase)];
					}
					y -= 1.0f;
				}
				[NSBezierPath strokeLineFromPoint: NSMakePoint(x, y) toPoint: NSMakePoint(x, ybase)];
			}
		}
		if (array != nil && draggingPath != nil) {
			[array addObject:[color colorWithAlphaComponent: 0.5f]];
			[array addObject:draggingPath];
			draggingPath = nil;
		}
		MDPointerRelease(pt);
	}
	if (array != nil) {
		int i = 0;
		n = (int)[array count];
		while (i < n) {
		//	NSLog(@"color: %@ path (%d)", [array objectAtIndex: i], [[array objectAtIndex: i + 1] elementCount]);
			[(NSColor *)[array objectAtIndex: i++] set];
			[[array objectAtIndex: i++] stroke];
		}
	}
}

- (void)drawBoxStripInRect: (NSRect)aRect
{
	float ppt;
	int32_t n;
	MDTickType beginTick, endTick;
	float height;
	float dx, dy;
	NSBezierPath *draggingPath;
	NSMutableArray *array;

	if (calib == NULL)
		return;

	height = [self bounds].size.height;
	ppt = [dataSource pixelsPerTick];
	draggingPath = nil;
	array = nil;
	if (stripDraggingMode > 0) {
		dx = draggingPoint.x - draggingStartPoint.x;
		dy = draggingPoint.y - draggingStartPoint.y;
		if (dx < -0.5 || dx > 0.5 || dy < -0.5 || dy > 0.5) {
			array = [NSMutableArray array];
			aRect.origin.x -= (dx > 0 ? dx : -dx);
			aRect.size.width += (dx > 0 ? dx : -dx) * 2;
		}
	}
	beginTick = (MDTickType)floor(aRect.origin.x / ppt);
	endTick = (MDTickType)ceil((aRect.origin.x + aRect.size.width) / ppt);
	MDCalibratorJumpToTick(calib, beginTick);
	if (eventKind == kMDEventTempo)
		n = 0;
	else
		n = [self visibleTrackCount] - 1;
	for ( ; n >= 0; n--) {
		float x, y, xlast, ylast;
		MDEvent *ep;
		MDPointer *pt;
		NSRect rect;
		NSColor *color, *shadowColor;
		MDTrack *track;
		int32_t trackNo, poslast;
		BOOL isFocused;
		if (eventKind == kMDEventTempo)
			trackNo = 0;
		else
			trackNo = [self sortedTrackNumberAtIndex: n];
		track = [[[dataSource document] myMIDISequence] getTrackAtIndex: trackNo];
		isFocused = [self isFocusTrack: trackNo];
		color = [[dataSource document] colorForTrack: trackNo enabled: isFocused];
		shadowColor = (isFocused ? [color shadowWithLevel: 0.1f] : color);
		pt = MDCalibratorCopyPointer(calib, track, eventKind, eventCode);
		if (pt == NULL)
			continue;
		ep = MDPointerCurrent(pt);
		if (ep == NULL) {
			xlast = ylast = 0;
			poslast = -1;
		} else {
			ylast = (float)(ceil((getYValue(ep, eventKind) - minValue) / (maxValue - minValue) * height));
			xlast = (float)(floor(MDGetTick(ep) * ppt));
			poslast = MDPointerGetPosition(pt);
		}
		while (1) {
			ep = MDPointerForward(pt);
			if (ep != NULL) {
				if (MDGetKind(ep) != eventKind)
					continue;
				if (eventCode != -1 && MDGetCode(ep) != eventCode)
					continue;
				y = (float)(ceil((getYValue(ep, eventKind) - minValue) / (maxValue - minValue) * height));
				x = (float)(floor(MDGetTick(ep) * ppt));
			} else {
				x = [self bounds].size.width;
			}
			rect = NSMakeRect(xlast, -1, x - xlast + 1, ylast + 1);
			if (NSIntersectsRect(rect, aRect)) {
				if ([[dataSource document] isSelectedAtPosition: poslast inTrack: trackNo]) {
					[color set];
					NSFrameRect(NSMakeRect(xlast - 1, ylast - 2, 3, 3));
					if (array != nil) {
						if (draggingPath == nil)
							draggingPath = [NSBezierPath bezierPath];
						[draggingPath appendBezierPathWithRect: NSMakeRect(xlast + dx - 1, ylast + dy - 2, 3, 3)];
						[draggingPath moveToPoint: NSMakePoint(xlast + dx, ylast + dy)];
						[draggingPath lineToPoint: NSMakePoint(xlast + dx, 0)];
					}
					[[NSColor whiteColor] set];
				} else {
					[shadowColor set];
				}
				[NSBezierPath fillRect: rect]; // NSRectFill(rect);
				[color set];
				[NSBezierPath strokeRect: rect]; // NSFrameRect(rect);
			}
			if (ep == NULL || xlast >= aRect.origin.x + aRect.size.width)
				break;
			xlast = x;
			ylast = y;
			poslast = MDPointerGetPosition(pt);
		}
		if (draggingPath != nil) {
			[array addObject:[color colorWithAlphaComponent: 0.5f]];
			[array addObject:draggingPath];
			draggingPath = nil;
		}
		MDPointerRelease(pt);
	}
	if (array != nil) {
		int i = 0;
		n = (int)[array count];
		while (i < n) {
			[(NSColor *)[array objectAtIndex: i++] set];
			[[array objectAtIndex: i++] stroke];
		}
	}
}

- (float)horizontalGridInterval
{
	NSRect frame, visibleRect;
	float visibleRange, aRange;
	frame = [self frame];
	visibleRect = [(NSClipView *)[self superview] documentVisibleRect];
	aRange = maxValue - minValue + 1.0f;
	visibleRange = aRange / frame.size.height * visibleRect.size.height;
	while (aRange > visibleRange * 0.7f)
		aRange *= 0.5f;
	return aRange;
}

- (void)drawContentsInRect: (NSRect)aRect
{
	NSPoint pt;
	NSRect bounds;
	float y, grid;
	NSEraseRect(aRect);
	[self paintEditingRange: aRect startX: NULL endX: NULL];
	if (eventKind == kMDEventNote || eventKind == kMDEventInternalNoteOff)
		[self drawVelocityInRect: aRect];
	else
		[self drawBoxStripInRect: aRect];

	/*  Draw grid lines  */
	bounds = [self bounds];
	pt.x = bounds.origin.x;
	grid = [self horizontalGridInterval];
	[[NSColor lightGrayColor] set];
	for (y = minValue + grid; y < maxValue; y += grid) {
		pt.y = (CGFloat)(floor(bounds.origin.x + y * (bounds.size.height / (maxValue - minValue))) + 0.5);
		[NSBezierPath strokeLineFromPoint: pt toPoint: NSMakePoint(pt.x + bounds.size.width, pt.y)];
	}
	if ([self isDragging])
		[self drawSelectRegion];
}

- (void)setKindAndCode: (int32_t)kindAndCode
{
	int newKind, newCode, ftrack;
	MDSequence *sequence;
	float minval, maxval;
	newKind = (kindAndCode >> 16) & 65535;
	newCode = kindAndCode & 65535;
	if ((newKind == 65535 || newKind == eventKind) && (newCode == 65535 || newCode == eventCode))
		return;  /*  Do nothing  */
	if (newKind != 65535) {
		eventKind = newKind;
		if (eventKind == kMDEventTempo) {
			minval = 0.0f;
			maxval = 511.0f;
		} else if (eventKind == kMDEventPitchBend) {
			minval = -8192.0f;
			maxval = 8191.0f;
		} else {
			minval = 0.0f;
			maxval = 127.0f;
		}
		[self setMinValue: minval];
		[self setMaxValue: maxval];
		if (eventKind == kMDEventNote || eventKind == kMDEventInternalNoteOff)
			mode = kStripChartBarMode;
		else
			mode = kStripChartBoxMode;
		[self setYScale: [[self superview] bounds].size.height / (maxval - minval)];
	}
	if (newCode != 65535)
		eventCode = newCode;
	else eventCode = -1;
	if (calib != NULL)
		MDCalibratorRelease(calib);
	calib = NULL;
	sequence = [[[dataSource document] myMIDISequence] mySequence];
	calib = MDCalibratorNew(sequence, NULL, kMDEventTempo, -1);
//	if (eventKind == kMDEventTempo) {
//		calib = MDCalibratorNew(sequence, NULL, eventKind, -1);
//	} else if (eventKind != kMDEventNote && eventKind != kMDEventInternalNoteOff) {
	if (eventKind != kMDEventTempo && eventKind != kMDEventNote && eventKind != kMDEventInternalNoteOff) {
		int i;
		MDTrack *track;
		for (i = [self visibleTrackCount] - 1; i >= 0; i--) {
			track = MDSequenceGetTrack(sequence, [self sortedTrackNumberAtIndex: i]);
			if (track != NULL) {
				if (calib == NULL)
					calib = MDCalibratorNew(sequence, track, eventKind, eventCode);
				else
					MDCalibratorAppend(calib, track, eventKind, eventCode);
			}
		}
	}
	ftrack = focusTrack;
	if (eventKind == kMDEventTempo)
		ftrack = 0;  /*  Conductor Track  */
	else if (ftrack == 0)
		ftrack = -1;  /*  As piano roll  */
	if (ftrack != focusTrack)
		[self setFocusTrack:ftrack];
	else {
		[self reloadData];
		[self setNeedsDisplay: YES];
	}
}

- (BOOL)isFocusTrack: (int)trackNum
{
	if (focusTrack >= 0)
		return (trackNum == focusTrack);
	else return [super isFocusTrack:trackNum];
}
- (int32_t)visibleTrackCount
{
	if (focusTrack >= 0)
		return 1;
	else return [super visibleTrackCount];
}

- (int)sortedTrackNumberAtIndex: (int)index
{
	if (focusTrack >= 0)
		return (index == 0 ? focusTrack : -1);
	else return [super sortedTrackNumberAtIndex:index];
}

- (void)setFocusTrack:(int)aTrack
{
	/*  TODO: We need to set the first responder to the active client view, rather than to the main view. Otherwise, pasted events will go to the 'editable' track in the track list instead of the focus track.  */
	int i;
	id view;
	focusTrack = aTrack;
	for (i = 0; (view = [dataSource clientViewAtIndex:i]) != nil; i++) {
		if (view == self) {
			[[dataSource splitterViewAtIndex:i] setTrack:aTrack];
			break;
		}
	}
	[self reloadData];
	[self setNeedsDisplay:YES];
}

- (int)focusTrack
{
	return focusTrack;
}

- (int32_t)kindAndCode
{
	return ((((int32_t)eventKind) & 65535) << 16) | (eventCode & 65535);
}

- (void)invalidateDraggingRegion
{
	NSRect rect = selectionRect;
	rect.origin.x += draggingPoint.x - draggingStartPoint.x;
	if (draggingPoint.y > draggingStartPoint.y)
		rect.size.height += draggingPoint.y - draggingStartPoint.y;
	rect = NSInsetRect(rect, -2, -2);
	dprintf(2, "invalidateDraggingRegion: (%g %g %g %g)\n", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
	[self setNeedsDisplayInRect: rect];
}

- (NSRect)boundRectForSelection
{
	int i, n;
	MDTickType tick, minTick, maxTick;
	float ppt;
//	float minY;
	float maxY;
	float height = [self bounds].size.height;
	MyDocument *document = [dataSource document];
	minTick = kMDMaxTick;
	maxTick = kMDNegativeTick;
//	minY = 10000000.0;
	maxY = -10000000.0f;
	ppt = [dataSource pixelsPerTick];
	for (i = 0; (n = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
		int index;
		MDPointer *pt;
		MDEvent *ep;
		float y;
		MDTrack *track = [[document myMIDISequence] getTrackAtIndex: n];
		IntGroup *pset = [[document selectionOfTrack: n] pointSet];
		if (track == NULL || pset == NULL)
			continue;
		pt = MDPointerNew(track);
		if (pt == NULL)
			break;
		MDPointerSetPositionWithPointSet(pt, pset, -1, &index);
		while ((ep = MDPointerForwardWithPointSet(pt, pset, &index)) != NULL) {
			if (MDGetKind(ep) != eventKind || (eventCode != -1 && MDGetCode(ep) != eventCode))
				continue;
			tick = MDGetTick(ep);
			y = getYValue(ep, eventKind);
		//	if (y < minY)
		//		minY = y;
			if (y > maxY)
				maxY = y;
			if (tick < minTick)
				minTick = tick;
			if (tick > maxTick)
				maxTick = tick;
		}
	}
	if (minTick > maxTick || maxY < 0) {
		return NSMakeRect(0, 0, 0, 0);
	} else {
	//	minY = (minY - minValue) / (maxValue - minValue) * height;
		maxY = (maxY - minValue) / (maxValue - minValue) * height;
		return NSMakeRect(minTick * ppt - 1, 0, (maxTick - minTick) * ppt + 3, maxY + 1);
	}
}

/*  Returns 0-3; 0: no event, 1: the hot spot, 2: on the vertical line, 3: on the horizontal line (box mode only) */
- (int)findStripUnderPoint: (NSPoint)aPoint track: (int *)outTrack position: (int32_t *)outPosition mdEvent: (MDEvent **)outEvent
{
	int num, i, retval;
	int trackNum;
	int32_t poslast;
	MDEvent *ep;
	float ppt = [dataSource pixelsPerTick];
	float x, y, xlast, ylast;
	float height = [self bounds].size.height;
	MyDocument *document = (MyDocument *)[dataSource document];
	MDTickType theTick;

	num = [self visibleTrackCount];
	theTick = (MDTickType)((aPoint.x - 1) / ppt);
	if (calib != NULL)
		MDCalibratorJumpToTick(calib, theTick);
	retval = 0;
	for (i = 0; i < num; i++) {
		MDTrack *track;
		MDPointer *pt;
		trackNum = [self sortedTrackNumberAtIndex: i];
		track = [[document myMIDISequence] getTrackAtIndex: trackNum];
		if (track == NULL)
			continue;
		if (eventKind != kMDEventNote && eventKind != kMDEventInternalNoteOff)
			pt = MDCalibratorCopyPointer(calib, track, eventKind, eventCode);
		else {
			pt = MDPointerNew(track);
			if (pt != NULL) {
				MDPointerJumpToTick(pt, theTick);
				MDPointerBackward(pt);
			}
		}
		if (pt == NULL)
			continue;
		ep = MDPointerCurrent(pt);
		if (ep == NULL) {
			xlast = ylast = 0;
			poslast = -1;
		} else {
			ylast = (float)ceil((getYValue(ep, eventKind) - minValue) / (maxValue - minValue) * height);
			xlast = (float)floor(MDGetTick(ep) * ppt);
			poslast = MDPointerGetPosition(pt);
		}
		while (retval == 0) {
			ep = MDPointerForward(pt);
			if (ep != NULL) {
				if (MDGetKind(ep) != eventKind)
					continue;
				if (eventCode != -1 && MDGetCode(ep) != eventCode)
					continue;
				y = (float)ceil((getYValue(ep, eventKind) - minValue) / (maxValue - minValue) * height);
				x = (float)floor(MDGetTick(ep) * ppt);
			} else {
				x = [self bounds].size.width + 2;
			}
			if (aPoint.x >= x - 1 && aPoint.x <= x + 1) {
				if (aPoint.y >= y - 1 && aPoint.y <= y + 1)
					retval = 1;
				else if (aPoint.y <= y + 1 || (poslast >= 0 && aPoint.y <= ylast + 1))
					retval = 2;
				poslast = MDPointerGetPosition(pt);
				break;	/* found */
			}
			if (aPoint.x < x - 1) {
				if (eventKind != kMDEventNote && eventKind != kMDEventInternalNoteOff) {
					/*  horizontal line: box mode  */
					if (poslast >= 0) {
						if (aPoint.y >= ylast - 1 && aPoint.y <= ylast + 1) {
							MDPointerSetPosition(pt, poslast);
							ep = MDPointerCurrent(pt);
							retval = 3;
						} else if (aPoint.y <= ylast) {
							/*  Stop searching, as the box hides events in the following tracks  */
							retval = -1;
						}
					}
				}
				break;
			}
			if (ep == NULL)
				break;
		}
		MDPointerRelease(pt);
		if (retval != 0)
			break;
	}
	if (retval > 0) {
		if (outTrack != NULL)
			*outTrack = trackNum;
		if (outPosition != NULL)
			*outPosition = poslast;
		if (outEvent != NULL)
			*outEvent = ep;
	} else if (retval < 0)
		retval = 0;
	return retval;
}

//  Override of the GraphicClientView method. Treats the pencil mode specifically.
- (void)drawSelectRegion
{
	int n;
	float saveLineWidth;
	NSPoint pt1, pt2, dp;
	NSRect r;
	NSBezierPath *path;

	n = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
	if (lineShape == 0 && (n == kGraphicIbeamSelectTool || n == kGraphicRectangleSelectTool)) {
		[super drawSelectRegion];
		return;
	}
	
	//  Pencil mode
	//  Set the line shape (>0): this is the indicator for pencil editing (used in the mouseUp handler)
//	lineShape = [[self dataSource] graphicLineShape];

	//  selectPoints is an instance variable of GraphicClientView
	n = (int)[selectPoints count];
	if (n == 0)
		return;
	[[NSColor cyanColor] set];
	pt1 = [[selectPoints objectAtIndex: 0] pointValue];
	if (n < 2) {
		[NSBezierPath fillRect: NSMakeRect(pt1.x - 1, pt1.y - 1, 2, 2)];
		return;
	}
	pt2 = [[selectPoints objectAtIndex: 1] pointValue];

	/*  Calculate the rect with pt1/pt2 at the corners  */
	r.origin = pt1;
	r.size.width = pt2.x - pt1.x;
	r.size.height = pt2.y - pt1.y;
	if (r.size.width < 0) {
		r.size.width = -r.size.width;
		r.origin.x = pt2.x;
	}
	if (r.size.height < 0) {
		r.size.height = -r.size.height;
		r.origin.y = pt2.y;
	}

	saveLineWidth = [NSBezierPath defaultLineWidth];
	[NSBezierPath setDefaultLineWidth: 1.0f];
	[NSBezierPath fillRect: NSMakeRect(pt1.x - 1, pt1.y - 1, 2, 2)];
	[NSBezierPath fillRect: NSMakeRect(pt2.x - 1, pt2.y - 1, 2, 2)];

	if (lineShape == kGraphicLinearShape) {
		[NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
	} else if (lineShape == kGraphicRandomShape) {
		[NSBezierPath strokeRect: NSInsetRect(r, -0.5f, -0.5f)];
	} else {
		const float *p;
		switch (lineShape) {
			case kGraphicParabolaShape:
				p = sParabolaPoints;
				break;
			case kGraphicArcShape:
				p = sArcPoints;
				break;
			case kGraphicSigmoidShape:
				p = sSigmoidPoints;
				break;
			default:
				return;
		}
		dp.x = pt2.x - pt1.x;
		dp.y = pt2.y - pt1.y;
		path = [NSBezierPath bezierPath];
		while (p[2] >= 0.0) {
			[path moveToPoint: NSMakePoint(pt1.x + dp.x * p[0], pt1.y + dp.y * p[1])];
			[path curveToPoint: NSMakePoint(pt1.x + dp.x * p[6], pt1.y + dp.y * p[7])
				controlPoint1: NSMakePoint(pt1.x + dp.x * p[2], pt1.y + dp.y * p[3])
				controlPoint2: NSMakePoint(pt1.x + dp.x * p[4], pt1.y + dp.y * p[5])];
			p += 6;
		}
		[path stroke];
		/*  Eye guide  */
		if (p[0] < 1.0 || p[1] < 1.0) {
			[[[NSColor cyanColor] colorWithAlphaComponent: 0.5f] set];
			[NSBezierPath strokeLineFromPoint: NSMakePoint(pt1.x + dp.x * p[0] + 0.5f, pt1.y + dp.y * p[1] + 0.5f) toPoint: NSMakePoint(pt2.x + 0.5f, pt2.y + 0.5f)];
		}
	}
	[NSBezierPath setDefaultLineWidth: saveLineWidth];
}

//  Calculate the value of cubic bezier coordinates from the parameter t
static float
cubicFunc(float t, const float *points)
{
	//  The control parameters are given as points[0, 2, 4, 6]
	float a0, a1, a2, a3;
	a0 = -points[0] + 3 * points[2] - 3 * points[4] + points[6];
	a1 = 3 * (points[0] - 2 * points[2] + points[4]);
	a2 = 3 * (-points[0] + points[2]);
	a3 = points[0];
	return a3 + t * (a2 + t * (a1 + t * a0));
}

//  Calculate the parameter t from the coordinate value
//  tt is the hint value for solving the equation.
static float
cubicReverseFunc(float x, const float *points, float tt)
{
	double a0, a1, a2, a3, dx, t, dxdt, t0, t1;
	int iter;
	a0 = -points[0] + 3 * points[2] - 3 * points[4] + points[6];
	a1 = 3 * (points[0] - 2 * points[2] + points[4]);
	a2 = 3 * (-points[0] + points[2]);
	a3 = points[0];
	t = tt;
	iter = 0;
	while (1) {
		dx = a3 + t * (a2 + t * (a1 + t * a0)) - x;
		if (fabs(dx) < 1e-8)
			return (float)t;
		dxdt = a2 + t * (2 * a1 + t * 3 * a0);
		if (++iter > 10 || fabs(dxdt) < 1e-8 || (t0 = t - dx / dxdt) >= 1.0 || t0 <= 0) {
			//  Switch to binary search
			if (dx < 0) {
				t0 = t;
				t1 = (a3 > x ? 0 : 1);
			} else {
				t1 = t;
				t0 = (a3 < x ? 0 : 1);
			}
			while (1) {
				t = (t0 + t1) / 2;
				dx = a3 + t * (a2 + t * (a1 + t * a0)) - x;
				if (dx < -1e-8) {
					t0 = t;
				} else if (dx > 1e-8) {
					t1 = t;
				} else return (float)t;
				if (fabs(t1 - t0) < 1e-8)
					return (float)t;
			}
		}
		if (fabs(t - t0) < 1e-8)
			return (float)t;
		t = t0;
	}
}

- (int)modifyLocalGraphicTool:(int)originalGraphicTool
{
	NSEvent *event = [NSApp currentEvent];
	unsigned int flags = [event modifierFlags];
	int tool = originalGraphicTool;
	if ((flags & NSCommandKeyMask) != 0) {
		if (tool == kGraphicPencilTool)
			tool = kGraphicRectangleSelectTool;
		else if (tool == kGraphicRectangleSelectTool)
			tool = kGraphicPencilTool;
	}
	return tool;
}

//  Edit in the pencil mode, i.e. edit the strip chart values according to 
//  the graphicLineShape and graphicEditingMode.
- (void)doPencilEdit
{
	int i, n;
	NSPoint pt1, pt2;
	MDTickType t1, t2;
	MDTickType fromTick, toTick;
	MDPointer *mdptr;
	float fromValue, toValue;
	float pixelsPerTick, height;
	const float *p;
	int v1, v2;
	int editingMode;
	BOOL shiftFlag = (([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) != 0);
	MyDocument *doc = (MyDocument *)[dataSource document];

	//  selectPoints is an instance variable of GraphicClientView
	n = (int)[selectPoints count];
	if (n == 0)
		return;
	pt1 = [[selectPoints objectAtIndex: 0] pointValue];
	if (n < 2)
		pt2 = pt1;
	else pt2 = [[selectPoints objectAtIndex: 1] pointValue];
	pixelsPerTick = [dataSource pixelsPerTick];
	height = [self bounds].size.height;
	t1 = (MDTickType)floor(pt1.x / pixelsPerTick + 0.5);
	t2 = (MDTickType)floor(pt2.x / pixelsPerTick + 0.5);
	v1 = (int)floor(pt1.y * (maxValue - minValue) / height + 0.5 + minValue);
	v2 = (int)floor(pt2.y * (maxValue - minValue) / height + 0.5 + minValue);
	if (t1 < t2) {
		fromTick = t1;
		toTick = t2;
		fromValue = v1;
		toValue = v2;
	} else {
		fromTick = t2;
		toTick = t1;
		fromValue = v2;
		toValue = v1;
	}
	if (t1 == t2 || lineShape == kGraphicRandomShape) {
		//  Let fromValue <= toValue
		if (fromValue > toValue) {
			float vw = fromValue;
			fromValue = toValue;
			toValue = vw;
		}
	}
	switch (lineShape) {
		case kGraphicParabolaShape:
			p = sParabolaPoints;
			break;
		case kGraphicArcShape:
			p = sArcPoints;
			break;
		case kGraphicSigmoidShape:
			p = sSigmoidPoints;
			break;
		default:
			p = NULL;
			break;
	}

	editingMode = [[self dataSource] graphicEditingMode];
	if (editingMode == kGraphicSetMode && eventKind != kMDEventNote && eventKind != kMDEventInternalNoteOff && !shiftFlag) {
		//  Generate a series of events
		MDTrackObject *trackObj;
		MDEvent event;
		trackObj = [[[MDTrackObject allocWithZone: [self zone]] init] autorelease];
		mdptr = MDPointerNew([trackObj track]);
		MDEventInit(&event);
		MDSetKind(&event, eventKind);
		MDSetCode(&event, eventCode);
		if (t1 == t2 || v1 == v2 || lineShape == kGraphicLinearShape || lineShape == kGraphicRandomShape) {
			MDTickType tick;
			float v, v0;
			tick = fromTick;
			v0 = -100000;
			while (1) {
				MDTickType tick2;
				if (t1 == t2)
					v = 1.0f;
				else if (lineShape == kGraphicRandomShape)
					v = (random() % 0x10000000) / (float)0x10000000;
				else
					v = (float)((double)(tick - fromTick) / (toTick - fromTick));
				v = v * (toValue - fromValue) + fromValue;
				//  Generate an event
				MDSetTick(&event, tick);
				if (eventKind == kMDEventTempo)
					MDSetTempo(&event, (float)floor(v));
				else
					MDSetData1(&event, (int)floor(v));
				if (v != v0 || tick >= toTick) {
					MDPointerInsertAnEvent(mdptr, &event);
					v0 = v;
				}
			//	NSLog(@"tick=%ld value=%d", tick, (int)floor(v));
				if (tick >= toTick)
					break;
				tick2 = MDCalibratorTimeToTick(calib, MDCalibratorTickToTime(calib, tick) + sTimeResolution);
				if (tick2 < tick + sTickResolution)
					tick2 = tick + sTickResolution;
				if (lineShape == kGraphicLinearShape) {
					MDTickType tick3;
					if (fabs(toValue - fromValue) < 1e-6)
						tick3 = toTick;
					else
						tick3 = tick + (MDTickType)floor(fabs(sValueResolution / (toValue - fromValue) * (toTick - fromTick)));
					if (tick3 > tick2)
						tick2 = tick3;
				}
				if (tick2 > toTick)
					tick = toTick;
				else tick = tick2;
			}
		} else if (p != NULL) {
			float x, y, v, t;
			int n;
			n = 0;
			while (p[2] >= 0.0f) {
				//  Initial point
				t = 0.0f;
				x = p[0];
				y = p[1];
				while (1) {
					float ta, tb, tc;
					float xa, xb, yc;
					MDTimeType tm;
					MDTickType tk;
					if (n == 0 || t > 0.0f) {
						//  Generate an event
						MDSetTick(&event, (MDTickType)(x * (t2 - t1) + t1));
						v = y * (v2 - v1) + v1;
						if (eventKind == kMDEventTempo)
							MDSetTempo(&event, (float)floor(v));
						else
							MDSetData1(&event, (int)floor(v));
						MDPointerInsertAnEvent(mdptr, &event);
					//	NSLog(@"t=%f tick=%ld value=%d", t, (MDTickType)(x * (t2 - t1) + t1), (int)floor(v));
					}
					if (t >= 1.0)
						break;
					xa = x + (float)fabs((double)sTickResolution / (t2 - t1));
					if (xa < p[6]) {
						ta = cubicReverseFunc(xa, p, t);
					} else ta = 1.0f;
					tm = MDCalibratorTickToTime(calib, (MDTickType)(x * (t2 - t1) + t1));
					if (t2 > t1)
						tm += sTimeResolution;
					else
						tm -= sTimeResolution;
					tk = MDCalibratorTimeToTick(calib, tm);
					xb = (float)((double)(tk - t1)) / (t2 - t1);
//					xb = (double)(MDCalibratorTimeToTick(calib, 
//						MDCalibratorTickToTime(calib, (MDTickType)(x * (t2 - t1) + t1))
//						+ sTimeResolution) - t1) / (t2 - t1);
					if (xb <= x) {  //  This can happen due to the round-off of tk
						tb = t;
					} else if (xb < p[6]) {
						tb = cubicReverseFunc(xb, p, t);
					} else tb = 1.0f;
					if (v1 == v2 || p[1] == p[7]) {
						tc = 1.0f;
					} else {
						yc = (float)((double)sValueResolution / (v2 - v1));
						if (p[1] < p[7]) {
							yc = y + (float)fabs(yc);
							if (yc < p[7])
								tc = cubicReverseFunc(yc, p + 1, t);
							else tc = 1.0f;
						} else {
							yc = y - (float)fabs(yc);
							if (yc > p[7])
								tc = cubicReverseFunc(yc, p + 1, t);
							else tc = 1.0f;
						}
					}
					t = (ta < tb ? tb : ta);
					t = (t < tc ? tc : t);
					x = cubicFunc(t, p);
					y = cubicFunc(t, p + 1);
				}
				p += 6;
				n++;
			}
		}
		MDPointerRelease(mdptr);
	//	MDTrackCheck([trackObj track]);
		if (MDTrackGetNumberOfEvents([trackObj track]) == 0)
			return;
		for (i = 0; (n = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
			IntGroup *insertedPositionSet;
			if (eventKind == kMDEventTempo && n != 0)
				continue;
			if (eventKind != kMDEventTempo && n == 0)
				continue;
			if ([self isFocusTrack:n]) {
				IntGroupObject *psetObj = [doc eventSetInTrack: n eventKind: eventKind eventCode: eventCode fromTick: fromTick toTick: toTick fromData: kMDMinData toData: kMDMaxData inPointSet: nil];
				[doc deleteMultipleEventsAt: psetObj fromTrack: n deletedEvents: NULL];
				if ([doc insertMultipleEvents: trackObj at: nil toTrack: n selectInsertedEvents: YES insertedPositions: &insertedPositionSet] && insertedPositionSet != NULL) {
					if (!shiftFlag) {
						MDSelectionObject *selObj = [[MDSelectionObject alloc] initWithMDPointSet:insertedPositionSet];
						[doc setSelection:selObj inTrack:n sender:self];
						[selObj release];
					}
				}
			}
		}
	} else {
		//  Modify the data of the existing events
		for (i = 0; (n = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
			MDEvent *ep;
			MDTrack *track;
			MDSelectionObject *psetObj;
			IntGroup *pset;
			int idx;
			int32_t count, j;
			NSMutableData *theData;
			float *fp;
			float x, y, t, v, v0;
			if (![self isFocusTrack:n])
				continue;
			if (eventKind == kMDEventTempo && n != 0)
				continue;
			if (eventKind != kMDEventTempo && n == 0)
				continue;
			track = [[[dataSource document] myMIDISequence] getTrackAtIndex: n];
			if (track == NULL)
				continue;
			psetObj = [doc eventSetInTrack: n eventKind: (eventKind == kMDEventInternalNoteOff ? kMDEventNote : eventKind) eventCode: eventCode fromTick: fromTick toTick: toTick fromData: kMDMinData toData: kMDMaxData inPointSet: (shiftFlag ? [doc selectionOfTrack: n] : nil)];
			if (psetObj == nil)
				continue;
			pset = [psetObj pointSet];
			count = IntGroupGetCount(pset);
			if (count == 0)
				continue;
			theData = [NSMutableData dataWithLength: count * sizeof(float)];
			fp = (float *)[theData mutableBytes];
			mdptr = MDPointerNew(track);
			idx = -1;
			if (t1 < t2)
				t = 0;
			else t = 1;
			for (j = 0; j < count; j++) {
				ep = MDPointerForwardWithPointSet(mdptr, [psetObj pointSet], &idx);
				if (ep == NULL)
					break;
				if (t1 == t2) {
					v = toValue;
				} else {
					x = (float)(((double)MDGetTick(ep) - t1) / (t2 - t1));
					if (lineShape == kGraphicLinearShape)
						y = x;
					else if (lineShape == kGraphicRandomShape)
						y = (random() % 0x10000000) / (float)0x10000000;
					else if (p != NULL) {
						const float *pp;
						for (pp = p; pp[2] >= 0; pp += 6) {
							if (pp[0] <= x && x <= pp[6])
								break;
						}
						if (pp[2] >= 0) {
							t = cubicReverseFunc(x, pp, t);
							y = cubicFunc(t, pp + 1);
						} else break;
					} else break;
					v = (float)floor(y * (v2 - v1) + v1 + 0.5);
				}
				switch (eventKind) {
					case kMDEventNote:
						v0 = MDGetNoteOnVelocity(ep);
						break;
					case kMDEventInternalNoteOff:
						v0 = MDGetNoteOffVelocity(ep);
						break;
					case kMDEventTempo:
						v0 = MDGetTempo(ep);
						break;
					default:
						v0 = MDGetData1(ep);
						break;
				}
				if (editingMode == kGraphicAddMode) {
					/*  The vertical center will be zero  */
					v = v0 + v - (maxValue - minValue + 1) * 0.5f;
				} else if (editingMode == kGraphicScaleMode) {
					/*  The full scale is 0..200%  */
					v = v0 * (v - minValue) / (maxValue - minValue + 1) * 2.0f;
				} else if (editingMode == kGraphicLimitMaxMode) {
					if (v0 < v)
						v = v0;
				} else if (editingMode == kGraphicLimitMinMode) {
					if (v0 > v)
						v = v0;
				}
				if (v < minValue)
					v = minValue;
				else if (v > maxValue)
					v = maxValue;
				fp[j] = v;
			}
			MDPointerRelease(mdptr);
			if ([doc modifyData: theData forEventKind: eventKind ofMultipleEventsAt: psetObj inTrack: n mode: MyDocumentModifySet]) {
				if (!shiftFlag) {
					[doc setSelection:psetObj inTrack:n sender:self];
				}
			}
		}
	}
}

- (NSString *)infoTextForMousePoint:(NSPoint)pt dragging:(BOOL)flag
{
	int yval;
	NSString *s;
	yval = (int)floor((maxValue - minValue) * pt.y / [self frame].size.height + minValue + 0.5);
	s = [[NSString stringWithFormat:@"%d, ", yval] stringByAppendingString:[super infoTextForMousePoint:pt dragging:flag]];
	if (!flag) {
		return s;
	} else {
		NSPoint pt0;
		if (selectPoints != nil && [selectPoints count] > 0) {
			pt0 = [[selectPoints objectAtIndex:0] pointValue];
			return [NSString stringWithFormat:@"%@-%@", [self infoTextForMousePoint:pt0 dragging:NO], s];
		} else return s;
	}
}

- (void)doMouseMoved: (NSEvent *)theEvent
{
	int track;
	int32_t pos;
	MDEvent *ep;
	int n;
	NSPoint pt = [NSEvent mouseLocation]; /*  Use mouseLocation in case this is called from flagsChanged: handler (not implemented yet)  */
	pt = [self convertPoint: [[self window] convertScreenToBase:pt] fromView: nil];
	localGraphicTool = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
	if (localGraphicTool == kGraphicPencilTool) {
		[[NSCursor pencilCursor] set];
		return;
	}
	n = [self findStripUnderPoint: pt track: &track position: &pos mdEvent: &ep];
	switch (n) {
		case 1:
			[[NSCursor moveAroundCursor] set];
			return;
		case 2:
			[[NSCursor horizontalMoveCursor] set];
			return;
		case 3:
			[[NSCursor verticalMoveCursor] set];
			return;
	}
	[super doMouseMoved: theEvent];
}

- (void)doMouseDown: (NSEvent *)theEvent
{
	int32_t pos;
	MDEvent *ep;
	int track;
	NSRect bounds;
	NSPoint pt;

	if (localGraphicTool == kGraphicPencilTool) {
		//  Invoke the common dragging procedure without checking mouse hitting on the existing chart
		//  The overridden method drawSelectRegion: implements the specific treatment
		//  for this class.
		[super doMouseDown: theEvent];
		lineShape = [[self dataSource] graphicLineShape];
		return;
	}
	
	lineShape = 0;	/*  Reset the line shape  */
	
	pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
	stripDraggingMode = [self findStripUnderPoint: pt track: &track position: &pos mdEvent: &ep];
	pt.x = [dataSource quantizedPixelFromPixel: pt.x];
	if (stripDraggingMode > 0) {
		float pixelQuantum;
		MyDocument *document = [dataSource document];
		if (![document isSelectedAtPosition: pos inTrack: track]) {
		//	int i, n;
		//	for (i = 0; (n = [self sortedTrackNumberAtIndex: i]) >= 0; i++)
		//		[document unselectAllEventsInTrack: n sender: self];
			[document unselectAllEventsInAllTracks: self];
			[document selectEventAtPosition: pos inTrack: track sender: self];
		}
		draggingStartPoint = draggingPoint = pt;
		horizontal = (stripDraggingMode == 2);
		[self displayIfNeeded];
		//  Calculate limit rectangle for the dragging point
		selectionRect = [self boundRectForSelection];
		bounds = [self bounds];
		limitRect = NSMakeRect(
			pt.x - (selectionRect.origin.x - bounds.origin.x),
			0,
			bounds.size.width - selectionRect.size.width,
			bounds.size.height);
		pixelQuantum = [dataSource pixelQuantum];
		limitRect.origin.x = [dataSource quantizedPixelFromPixel: limitRect.origin.x];
		if (limitRect.origin.x < 0.0)
			limitRect.origin.x += pixelQuantum;
		limitRect.size.width = (CGFloat)(floor(limitRect.size.width / pixelQuantum) * pixelQuantum);
		if (limitRect.size.width + limitRect.origin.x > bounds.origin.x + bounds.size.width)
			limitRect.size.width -= pixelQuantum;
	//	[super doMouseDown: theEvent];
		return;
	}

	[super doMouseDown: theEvent];
}

- (void)doMouseDragged: (NSEvent *)theEvent
{
	//  Pencil mode: invoke the common dragging procedure
	//  The overridden method drawSelectRegion: implements the specific treatment
	//  for this class.
	if (lineShape > 0) {
		[super doMouseDragged: theEvent];
		return;
	}
	
	if (stripDraggingMode > 0) {
		NSPoint pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
		BOOL optionDown = (([theEvent modifierFlags] & NSAlternateKeyMask) != 0);
		pt.x = [dataSource quantizedPixelFromPixel: pt.x];
		//  Support autoscroll (cf. GraphicClientView.mouseDragged)
	/*	if (autoscrollTimer != nil) {
			[autoscrollTimer invalidate];
			[autoscrollTimer release];
			autoscrollTimer = nil;
		} */
		if (stripDraggingMode == 1) {
			/*  horizontal or vertical, depending on the mouse position  */
			NSSize delta;
			delta.width = (CGFloat)fabs(pt.x - draggingStartPoint.x);
			delta.height = (CGFloat)fabs(pt.y - draggingStartPoint.y);
			if (delta.width > 3 || delta.height > 3)
				horizontal = (delta.width > delta.height);
			if (horizontal) {
				if (optionDown)
					[[NSCursor horizontalMovePlusCursor] set];
				else
					[[NSCursor horizontalMoveCursor] set];					
			} else {
				/*  Note: no duplicate on vertical move with option key  */
				[[NSCursor verticalMoveCursor] set];
			}
		}
		if (horizontal)
			pt.y = draggingStartPoint.y;
		else
			pt.x = draggingStartPoint.x;
	/*	pt = [self convertPoint: pt toView: nil];
	//	[self invalidateDraggingRegion];
		if ([self autoscroll: [theEvent mouseEventWithLocation: pt]])
			autoscrollTimer = [[NSTimer scheduledTimerWithTimeInterval: 0.2 target: self selector:@selector(autoscrollTimerCallback:) userInfo: theEvent repeats: NO] retain];
		pt = [self convertPoint: pt fromView: nil]; */
		if (pt.x < limitRect.origin.x)
			pt.x = limitRect.origin.x;
		else if (pt.x > limitRect.origin.x + limitRect.size.width)
			pt.x = limitRect.origin.x + limitRect.size.width;
		if (pt.y < limitRect.origin.y)
			pt.y = limitRect.origin.y;
		else if (pt.y > limitRect.origin.y + limitRect.size.height)
			pt.y = limitRect.origin.y + limitRect.size.height;
		[self invalidateDraggingRegion];
		draggingPoint = pt;
		[self invalidateDraggingRegion];
		[self displayIfNeeded];
	} else [super doMouseDragged: theEvent];
}

- (void)doMouseUp: (NSEvent *)theEvent
{
	int i, trackNo;
	float ppt;
	float height;
	MyDocument *document;
	MDTickType minTick, maxTick;
	NSRect bounds;
	
	//  Pencil mode: edit the strip chart values according to the line shape and 
	//  editing mode
	if (lineShape > 0) {
		[self doPencilEdit];
		lineShape = 0;
		return;
	}
	
	if (stripDraggingMode > 0) {
		NSPoint pt;
		MDTickType deltaTick;
		float deltaValue;
		BOOL optionDown = (([theEvent modifierFlags] & NSAlternateKeyMask) != 0);
		[self invalidateDraggingRegion];
		pt.x = draggingPoint.x - draggingStartPoint.x;
		pt.y = draggingPoint.y - draggingStartPoint.y;
		deltaTick = (MDTickType)floor(pt.x / [dataSource pixelsPerTick] + 0.5);
		deltaValue = (MDTickType)floor(pt.y * (maxValue - minValue) / [self bounds].size.height + 0.5);
		[dataSource dragEventsOfKind: eventKind andCode: eventCode byTick: deltaTick andValue: deltaValue sender: self optionFlag: optionDown];
		stripDraggingMode = 0;
		[self displayIfNeeded];
		return;
	} else if (!isDragging || isLoupeDragging) {
		[super doMouseUp: theEvent];
		return;
	}

	/*  Change selection  */
	bounds = [[self selectionPath] bounds];
	height = [self bounds].size.height;
	ppt = [dataSource pixelsPerTick];
	minTick = (MDTickType)(bounds.origin.x / ppt);
	maxTick = (MDTickType)((bounds.origin.x + bounds.size.width) / ppt);
	document = (MyDocument *)[dataSource document];
	for (i = 0; (trackNo = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
		MDTrack *track;
		MDPointer *pt;
		MDEvent *ep;
		IntGroup *pset;
		MDSelectionObject *obj;
		if (![self isFocusTrack:trackNo])
			continue;
		track = [[document myMIDISequence] getTrackAtIndex: trackNo];
		if (track == NULL)
			continue;
		pt = MDPointerNew(track);
		if (pt == NULL)
			break;
		pset = IntGroupNew();
		if (pset == NULL)
			break;
		MDPointerJumpToTick(pt, minTick);
		MDPointerBackward(pt);
		while ((ep = MDPointerForward(pt)) != NULL && MDGetTick(ep) < maxTick) {
			NSPoint point;
			if (MDGetKind(ep) != eventKind)
				continue;
			if (eventCode != -1 && MDGetCode(ep) != eventCode)
				continue;
			point.y = (CGFloat)ceil((getYValue(ep, eventKind) - minValue) / (maxValue - minValue) * height);
			point.x = (CGFloat)floor(MDGetTick(ep) * ppt);
		//	point.x = floor(MDGetTick(ep) * ppt);
		//	point.y = floor(MDGetCode(ep) * ys + 0.5) + 0.5 * ys;
			if ([self isPointInSelectRegion: point]) {
				if (IntGroupAdd(pset, MDPointerGetPosition(pt), 1) != kMDNoError)
					break;
			}
		}
		obj = [[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: pset];
		if (currentModifierFlags & NSShiftKeyMask) {
			[document toggleSelection: obj inTrack: trackNo sender: self];
		} else {
			[document setSelection: obj inTrack: trackNo sender: self];
		}
		[obj release];
		IntGroupRelease(pset);
		MDPointerRelease(pt);
	}
}

- (void)startExternalDraggingAtPoint:(NSPoint)aPoint mode:(int)aMode
{
	stripDraggingMode = aMode;
	draggingStartPoint = draggingPoint = aPoint;
	[self setNeedsDisplay:YES];
}

- (void)endExternalDragging
{
	stripDraggingMode = 0;
	[self setNeedsDisplay:YES];
}

- (void)setExternalDraggingPoint:(NSPoint)aPoint
{
	draggingPoint = aPoint;
	[self setNeedsDisplay:YES];
}

@end
