/*
    PianoRollView.m
*/
/*
    Copyright (c) 2000-2017 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "PianoRollView.h"
#import "GraphicWindowController.h"
#import "StripChartView.h"
#import "MyDocument.h"
#import "MyMIDISequence.h"
#import "MDObjects.h"
#import "NSEventAdditions.h"
#import "NSCursorAdditions.h"

#include <math.h>	/*  for floor(), ceil() */

@implementation PianoRollView

static CGFloat sLineDash1[] = {6.0f, 2.0f};
static CGFloat sLineDash2[] = {2.0f, 6.0f};
static CGFloat sDashWidth = 8.0f;

- (id)initWithFrame: (NSRect)rect
{
    self = [super initWithFrame: rect];
	if (self) {
		autoScaleOnResizing = NO;
	}
    return self;
}

- (void)dealloc
{
	[super dealloc];
}

- (int)clientViewType
{
	return kGraphicPianoRollViewType;
}

- (void)drawVerticalLinesInRect: (NSRect)aRect
{
	float ppt;
	MDTickType beginTick, endTick, duration;
	float originx, limitx;
	NSPoint pt1, pt2;
	int i, numLines;
	NSBezierPath *lines, *subLines;
	ppt = [dataSource pixelsPerTick];
	beginTick = aRect.origin.x / ppt;
	endTick = (aRect.origin.x + aRect.size.width) / ppt + 1;
	duration = [dataSource sequenceDuration];
	limitx = duration * ppt;
	pt1.y = (CGFloat)(floor(aRect.origin.y / sDashWidth) * sDashWidth);
	pt2.y = (CGFloat)(ceil((aRect.origin.y + aRect.size.height) / sDashWidth) * sDashWidth);
	lines = [[NSBezierPath allocWithZone: [self zone]] init];
	subLines = [[NSBezierPath allocWithZone: [self zone]] init];
	originx = aRect.origin.x;
	if (originx == 0.0f)
		originx = 1.0f;	/*  Avoid drawing line at tick = 0  */
	pt2.x = 0.0f;
	while (beginTick < endTick) {
		int mediumCount, majorCount;
		MDEvent *sig1, *sig2;
		MDTickType sigTick, nextSigTick;
		float interval, startx;
		[dataSource verticalLinesFromTick: beginTick timeSignature: &sig1 nextTimeSignature: &sig2 lineIntervalInPixels: &interval mediumCount: &mediumCount majorCount: &majorCount];
		sigTick = (sig1 == NULL ? 0 : MDGetTick(sig1));
		nextSigTick = (sig2 == NULL ? kMDMaxTick : MDGetTick(sig2));
		if (nextSigTick > endTick)
			nextSigTick = endTick;
		startx = sigTick * ppt;
		numLines = (int)floor((nextSigTick - sigTick) * ppt / interval) + 1;
		i = (startx >= originx ? 0 : (int)floor((originx - startx) / interval));
		for ( ; i < numLines; i++) {
			pt1.x = (CGFloat)(floor(startx + i * interval) + 0.5);
			if (pt1.x >= originx && pt1.x <= aRect.origin.x + aRect.size.width) {
				if (pt1.x > limitx && pt2.x <= limitx) {
					/*  Draw the lines and set the color to gray  */
					[lines setLineDash: sLineDash1 count: 2 phase: 0.0f];
					[subLines setLineDash: sLineDash2 count: 2 phase: 0.0f];
					[lines stroke];
					[subLines stroke];
					[lines removeAllPoints];
					[subLines removeAllPoints];
					[[NSColor grayColor] set];
				}
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
	[lines setLineDash: sLineDash1 count: 2 phase: 0.0f];
	[subLines setLineDash: sLineDash2 count: 2 phase: 0.0f];
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

- (void)drawStavesInRect: (NSRect)aRect
{
	int index, n, i;
	NSPoint pt1, pt2;
	float ys, limitx, startx, endx;
	NSBezierPath *staves, *subStaves, *path;

	staves = [[NSBezierPath allocWithZone: [self zone]] init];
	subStaves = [[NSBezierPath allocWithZone: [self zone]] init];
	limitx = [dataSource sequenceDuration] * [dataSource pixelsPerTick];
	index = 0;
	/*  Line start/end points are set to multiples of sDashWidth to avoid complication of calculating appropriate phase for setLineDash: */
	startx = (float)(sDashWidth * floor(aRect.origin.x / sDashWidth));
	endx = (float)(sDashWidth * ceil((aRect.origin.x + aRect.size.width) / sDashWidth + 1.0));
	ys = [self yScale];
	for (i = 0; i < 2; i++) {
		if (i == 0) {
			if (limitx >= aRect.origin.x + aRect.size.width)
				continue;
			[[NSColor grayColor] set];
			pt1.x = sDashWidth * (float)floor(limitx / sDashWidth);
			pt2.x = endx;
		} else {
			[staves removeAllPoints];
			[subStaves removeAllPoints];
			[[NSColor blackColor] set];
			pt1.x = startx;
			if (limitx < aRect.origin.x + aRect.size.width)
				pt2.x = limitx;
			else pt2.x = endx;
		}
		for (index = -17; index <= +19; index++) {
			n = MDEventStaffIndexToNoteNumber(index);
			if (n < 0 || n >= 128)
				continue;
			path = ((n >= 43 && n <= 77 && n != 60) ? staves : subStaves);
			pt1.y = (CGFloat)(floor((n + 0.5) * ys) + 0.5);
			pt2.y = pt1.y;
			[path moveToPoint: pt1];
			[path lineToPoint: pt2];
		}
		[staves setLineDash: sLineDash1 count: 2 phase: 0.0f];
		[subStaves setLineDash: sLineDash2 count: 2 phase: 0.0f];
		[staves stroke];
		[subStaves stroke];
	}
	[staves release];
	[subStaves release];
}

- (void)cacheNotesBeforeTick: (MDTickType)tick
{
	int num, trackNum, i;
	MDTrack *track;
	IntGroup *pset;
//	MDPointer *pt;
//	MDEvent *ep;
	[cacheArray release];
	num = [self visibleTrackCount];
	cacheArray = [[NSMutableArray allocWithZone: [self zone]] initWithCapacity: num + 1];
	cacheTick = tick;
	for (i = 0; i <= num; i++) {
		if (i == num) {
			track = [[[dataSource document] myMIDISequence] recordTrack];
			if (track == NULL)
				break;
			trackNum = -1;
		} else {
			trackNum = [self sortedTrackNumberAtIndex: i];
			track = [[[dataSource document] myMIDISequence] getTrackAtIndex: trackNum];
		}
	#if 1
		pset = MDTrackSearchEventsWithDurationCrossingTick(track, tick);
//		fprintf(stderr, "%s[%d]: track %p tick %ld, ", __FILE__, __LINE__, track, (int32_t)tick); IntGroupDump(pset);
	#else
		pset = IntGroupNew();
		if (pset != NULL) {
			pt = MDPointerNew(track);
			if (pt != NULL) {
				MDPointerJumpToTick(pt, tick);
				while ((ep = MDPointerBackward(pt)) != NULL) {
					if (MDGetKind(ep) == kMDEventNote && MDGetTick(ep) + MDGetDuration(ep) >= tick)
						IntGroupAdd(pset, MDPointerGetPosition(pt), 1);
				}
				MDPointerRelease(pt);
			}
		}
	//	fprintf(stderr, "%s[%d]: ", __FILE__, __LINE__);
	//	IntGroupDump(pset);
	#endif
		[cacheArray addObject: [[[IntGroupObject allocWithZone: [self zone]] initWithMDPointSet: pset] autorelease]];
		if (pset != NULL)
			IntGroupRelease(pset);
	}
}

static void
appendNotePath(NSBezierPath *path, float x1, float x2, float y, float ys)
{
	if (x2 - x1 <= ys) {
		[path appendBezierPathWithOvalInRect: NSMakeRect(x1, y, x2 - x1, ys)];
	} else {
		float ys2 = ys * 0.5f;
		[path moveToPoint: NSMakePoint(x1 + ys2, y)];
		[path lineToPoint: NSMakePoint(x2 - ys2, y)];
		[path appendBezierPathWithArcWithCenter: NSMakePoint(x2 - ys2, y + ys2) radius: ys2 startAngle: -90.0f endAngle: 90.0f];
		[path lineToPoint: NSMakePoint(x1 + ys2, y + ys)];
		[path appendBezierPathWithArcWithCenter: NSMakePoint(x1 + ys2, y + ys2) radius: ys2 startAngle: 90.0f endAngle: -90.0f];
		[path closePath];
	}
}

- (void)drawNotesInRect: (NSRect)aRect selectionOnly: (BOOL)selectionOnly offset: (NSPoint)offset addDuration: (MDTickType)addDuration
{
	int num, i;
	NSBezierPath *normalPath, *selectedPath;
	NSRect rect = [self visibleRect];
	float ppt = [dataSource pixelsPerTick];
	float ys = [self yScale];
	MyDocument *document = (MyDocument *)[dataSource document];
	MDTickType originTick = (MDTickType)(rect.origin.x / ppt);
	MDTickType startTick, endTick;
	int startNote, endNote;
	MDTickType duration;
	static CGFloat sDash[] = { 2, 2 };
	BOOL isDraggingImage = NO;
	
	if (draggingMode > 0 && draggingMode < 3 && draggingImage != nil)
		isDraggingImage = YES;

	num = [self visibleTrackCount];
	if (cacheArray == nil || originTick != cacheTick)
		[self cacheNotesBeforeTick: originTick];
	normalPath = [[NSBezierPath allocWithZone: [self zone]] init];
	selectedPath = [[NSBezierPath allocWithZone: [self zone]] init];
	if (isDraggingImage)
		[selectedPath setLineDash:sDash count:2 phase:0.0f];
	startTick = (MDTickType)(aRect.origin.x / ppt);
	endTick = (MDTickType)((aRect.origin.x + aRect.size.width) / ppt);
//	NSLog(@"drawNotesInRect: startTick %ld endTick %ld", (int32_t)startTick, (int32_t)endTick);
	startNote = (int)floor(aRect.origin.y / ys);
	endNote = (int)ceil((aRect.origin.y + aRect.size.height) / ys);
	for (i = num; i >= 0; i--) {
		int trackNum;
		int n;
		MDTrack *track;
		IntGroup *pset;
		MDPointer *pt;
		MDEvent *ep;
		NSColor *color;
		float x1, x2, y;
		BOOL isFocus;
		if (i == num) {
			track = [[document myMIDISequence] recordTrack];
			if (track == NULL)
				continue;
			trackNum = -1;
			isFocus = NO;
		} else {
			trackNum = [self sortedTrackNumberAtIndex: i];
			track = [[document myMIDISequence] getTrackAtIndex: trackNum];
			if (track == NULL)
				continue;
			isFocus = [dataSource isFocusTrack: trackNum];
		}
		if (i >= [cacheArray count])
			continue;  /*  Nothing to draw  */
		pset = [[cacheArray objectAtIndex: i] pointSet];
		pt = MDPointerNew(track);
		if (pt != NULL)
			MDPointerSetPositionWithPointSet(pt, pset, -1, &n);
		while (pt != NULL) {  /*  Infinite loop  */
			MDTickType tick2;
			int note;
			NSBezierPath *path;
			BOOL selected;
			/*  Loop the note events; first in pset, then from originTick */
			if (pset != NULL) {
				while ((ep = MDPointerForwardWithPointSet(pt, pset, &n)) != NULL && MDGetKind(ep) != kMDEventNote)
					;
			//	fprintf(stderr, "%s[%d]: ep=%p pos=%ld n=%ld\n", __FILE__, __LINE__, ep, (int32_t)MDPointerGetPosition(pt), (int32_t)n);
				if (ep == NULL) {
					pset = NULL;
					MDPointerJumpToTick(pt, originTick);
					MDPointerBackward(pt);
					continue;
				}
			} else {
				while ((ep = MDPointerForward(pt)) != NULL && MDGetTick(ep) < endTick && MDGetKind(ep) != kMDEventNote)
					;
			}
			if (ep == NULL || MDGetTick(ep) >= endTick) {
				break;
			}
			if (trackNum >= 0)
				selected = [document isSelectedAtPosition: MDPointerGetPosition(pt) inTrack: trackNum];
			else selected = NO;
			duration = MDGetDuration(ep);
			if (addDuration != 0 && selected) {
				duration += addDuration;
				if (duration <= 0)
					duration = 1;
				else if (duration >= kMDMaxTick / 2)
					duration = kMDMaxTick / 2;
			}
			if ((tick2 = MDGetTick(ep) + duration) < startTick || (note = MDGetCode(ep)) < startNote || note > endNote)
				continue;	/*  Need not draw this one  */
			x1 = (float)floor(MDGetTick(ep) * ppt);
			x2 = (float)floor(tick2 * ppt);
			y = (float)floor(note * ys + 0.5);
		//	if (isDragging && !pencilOn && !isLoupeDragging && draggingMode == 0 && isFocus) {
			if (isFocus && !isLoupeDragging && selectionPath != nil) {
				/*  Change selection by dragging  */
				if ([self isPointInSelectRegion: NSMakePoint(x1, y + 0.5f * ys)]) {
					if (currentModifierFlags & NSShiftKeyMask)
						selected = !selected;
					else
						selected = YES;
				}
			}
			if (selectionOnly && !selected)
				continue;  /* Need not draw this one */
			if (selected)
				path = selectedPath;
			else path = normalPath;
			x1 += offset.x;
			x2 += offset.x;
			y += offset.y;
			appendNotePath(path, x1, x2, y, ys);
/*			if (x2 - x1 <= ys) {
				[path appendBezierPathWithOvalInRect: NSMakeRect(x1, y, x2 - x1, ys)];
			} else {
				float ys2 = ys * 0.5;
				[path moveToPoint: NSMakePoint(x1 + ys2, y)];
				[path lineToPoint: NSMakePoint(x2 - ys2, y)];
				[path appendBezierPathWithArcWithCenter: NSMakePoint(x2 - ys2, y + ys2) radius: ys2 startAngle: -90.0 endAngle: 90.0];
				[path lineToPoint: NSMakePoint(x1 + ys2, y + ys)];
				[path appendBezierPathWithArcWithCenter: NSMakePoint(x1 + ys2, y + ys2) radius: ys2 startAngle: 90.0 endAngle: -90.0];
				[path closePath];
			} */
		}
		if (pencilOn && isFocus) {
			/*  Drawing note  */
		/*	x1 = draggingStartPoint.x;
			x2 = draggingPoint.x;
			if (x2 < x1) {
				x2 = x1;
				x1 = draggingPoint.x;
			} else if (x2 == x1) {
				x2 = x1 + [dataSource pixelsPerQuarter];
			}
			y = floor(draggingStartPoint.y / ys) * ys; */
			x1 = draggingPoint.x;
			x2 = x1 + [dataSource pixelsPerQuarter];
			y = (float)(floor(draggingPoint.y / ys) * ys);
			appendNotePath(selectedPath, x1, x2, y, ys);
		}
		color = [document colorForTrack: (trackNum >= 0 ? trackNum : 0) enabled: isFocus];
		[[NSColor whiteColor] set];
		[selectedPath fill];
		[color set];
		[selectedPath stroke];
		if (!selectionOnly)
			[normalPath fill];
		[selectedPath removeAllPoints];
		[normalPath removeAllPoints];
	}
	[selectedPath release];
	[normalPath release];
}

- (void)drawContentsInRect: (NSRect)aRect
{
	MDTickType deltaDuration;
	if (draggingMode == 3)
		deltaDuration = (MDTickType)floor((MDTickType)((draggingPoint.x - draggingStartPoint.x) / [dataSource pixelsPerTick]) + 0.5);
	else deltaDuration = 0;
	NSEraseRect(aRect);
	[self paintEditingRange: aRect startX: NULL endX: NULL];
	[self drawVerticalLinesInRect: aRect];
	[self drawStavesInRect: aRect];
	[self drawNotesInRect: aRect selectionOnly: NO offset: NSMakePoint(0,0) addDuration: deltaDuration];
	if (draggingMode > 0) {
		if (draggingImage != nil) {
			NSSize size;
			if (draggingMode == 3) {
				//  Changing duration
			//	rect = NSMakeRect(0, 0, aRect.size.width, aRect.size.height);
			//	[draggingImage lockFocus];
			//	[[NSColor clearColor] set];
			//	NSRectFill(rect);
			//	[self drawNotesInRect: aRect selectionOnly: YES offset: NSMakePoint(-aRect.origin.x, -aRect.origin.y) addDuration: (MDTickType)((draggingPoint.x - draggingStartPoint.x) / [dataSource pixelsPerTick])];
			//	[draggingImage unlockFocus];
			//	[draggingImage dissolveToPoint: aRect.origin fromRect: rect fraction: 0.8];
			} else {
				size = [draggingImage size];
				[draggingImage drawAtPoint:NSMakePoint(draggingPoint.x - size.width / 2, draggingPoint.y - size.height / 2) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:0.8f];
			}
		}
	}
	[self drawSelectRegion];
	if (rubbingArray != nil) {
		NSPoint pt;
		pt.x = (CGFloat)(floor(rubbingTick * [dataSource pixelsPerTick]) + 0.5);
		pt.y = aRect.origin.y;
		[[NSColor blueColor] set];
		[NSBezierPath strokeLineFromPoint:pt toPoint:NSMakePoint(pt.x, pt.y + aRect.size.height)];
	}
}

- (void)reloadData
{
	[super reloadData];
	[cacheArray release];
	cacheArray = nil;
}

- (NSRect)willInvalidateSelectRect: (NSRect)rect
{
	float ys, y0, y1;
	NSRect visibleRect;
	/*  Redraw whole horizontal area, to avoid partial redrawing of a single note  */
	ys = [self yScale];
	y0 = (float)(floor(rect.origin.y / ys)) * ys - 1;
	y1 = (float)(ceil((rect.origin.y + rect.size.height) / ys) + 1.0) * ys + 1;
	rect.origin.y = y0;
	rect.size.height = y1 - y0;
	visibleRect = [self visibleRect];
	rect.origin.x = visibleRect.origin.x;
	rect.size.width = visibleRect.size.width;
	return rect;
}

/*  Returns 0-3; 0: no note, 1: left 1/3 of a note, 2: middle 1/3 of a note,
    3: right 1/3 of a note  */
- (int)findNoteUnderPoint: (NSPoint)aPoint track: (int32_t *)outTrack position: (int32_t *)outPosition mdEvent: (MDEvent **)outEvent
{
	int num, i;
	NSRect rect = [self visibleRect];
	float ppt = [dataSource pixelsPerTick];
	float ys = [self yScale];
	MyDocument *document = (MyDocument *)[dataSource document];
	MDTickType originTick = (MDTickType)(rect.origin.x / ppt);
	MDTickType limitTick = (MDTickType)((rect.origin.x + rect.size.width) / ppt);
	MDTickType theTick;
	int theNote;

	num = [self visibleTrackCount];
	theTick = (MDTickType)(aPoint.x / ppt);
	theNote = (int)floor(aPoint.y / ys);
	for (i = 0; i < num; i++) {
		int trackNum;
		int n;
		MDTrack *track;
		IntGroup *pset;
		MDPointer *pt;
		MDEvent *ep;
		MDTickType duration;
		trackNum = [self sortedTrackNumberAtIndex: i];
		if (![self isFocusTrack:trackNum])
			continue;
		track = [[document myMIDISequence] getTrackAtIndex: trackNum];
		if (track == NULL)
			continue;
		pt = MDPointerNew(track);
		if (pt == NULL)
			break;
//		pset = [[cacheArray objectAtIndex: i] pointSet];
//		MDPointerSetPositionWithPointSet(pt, pset, -1, &n);
		pset = NULL;
		MDPointerJumpToTick(pt, theTick);
		while (1) {
			MDTickType tick2;
			if (pset == NULL) {
				ep = MDPointerBackward(pt);
				if (ep != NULL && MDGetTick(ep) < originTick)
					ep = NULL;
			} else {
				ep = MDPointerBackwardWithPointSet(pt, pset, &n);
			}
			if (ep == NULL) {
				if (pset == NULL && cacheArray != nil && (pset = [[cacheArray objectAtIndex: i] pointSet]) != NULL) {
					MDPointerForward(pt);  //  We should retry the last 'failed' event
					n = -1;  //  The next MDPointerBackwardWithPointSet() will give the last event in pset
					continue;
				}
				else break;  // not found in this track
			}
			if (MDGetKind(ep) != kMDEventNote || MDGetCode(ep) != theNote || (tick2 = theTick - MDGetTick(ep)) > MDGetDuration(ep))
				continue;
			if (outTrack != NULL)
				*outTrack = trackNum;
			if (outPosition != NULL)
				*outPosition = MDPointerGetPosition(pt);
			if (outEvent != NULL)
				*outEvent = ep;
			MDPointerRelease(pt);
			duration = MDGetDuration(ep);
			//  The return value is determined by the visible part of the note
			if (MDGetTick(ep) + duration > limitTick) {
				duration = limitTick - MDGetTick(ep);
			}
			if (MDGetTick(ep) < originTick) {
				tick2 = theTick - originTick;
				duration = MDGetTick(ep) + duration - originTick;
			}
			if (tick2 < duration / 3)
				return 1;
			else if (tick2 < duration * 2 / 3)
				return 2;
			else return 3;
		}
		MDPointerRelease(pt);
	}
	return 0;
}

- (NSRect)boundRectForSelection
{
	int i, n;
	short note, minNote, maxNote;
	MDTickType tick, minTick, maxTick;
	float ys, ppt;
	MyDocument *document = [dataSource document];
	minTick = kMDMaxTick;
	maxTick = kMDNegativeTick;
	minNote = 128;
	maxNote = -1;
	ys = [self yScale];
	ppt = [dataSource pixelsPerTick];
	for (i = 0; (n = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
		int index;
		MDPointer *pt;
		MDEvent *ep;
		MDTrack *track = [[document myMIDISequence] getTrackAtIndex: n];
		IntGroup *pset = [[document selectionOfTrack: n] pointSet];
		if (track == NULL || pset == NULL)
			continue;
		pt = MDPointerNew(track);
		if (pt == NULL)
			break;
		MDPointerSetPositionWithPointSet(pt, pset, -1, &index);
		while ((ep = MDPointerForwardWithPointSet(pt, pset, &index)) != NULL) {
			if (MDGetKind(ep) != kMDEventNote)
				continue;
			note = MDGetCode(ep);
			tick = MDGetTick(ep);
			if (note < minNote)
				minNote = note;
			if (note > maxNote)
				maxNote = note;
			if (tick < minTick)
				minTick = tick;
			if (tick + MDGetDuration(ep) > maxTick)
				maxTick = tick + MDGetDuration(ep);
		}
	}
	if (minTick > maxTick || minNote > maxNote) {
		return NSMakeRect(0, 0, 0, 0);
	} else {
		return NSMakeRect(minTick * ppt, minNote * ys, (maxTick - minTick) * ppt, (maxNote - minNote + 1) * ys);
	}
}

- (void)setDraggingCursor: (int)mode
{
	switch (mode) {
		case 1:
			[[NSCursor horizontalMoveCursor] set];
			break;
		case 2:
			[[NSCursor verticalMoveCursor] set];
			break;
		case 3:
			[[NSCursor stretchCursor] set];
			break;
		case 17:
			[[NSCursor horizontalMovePlusCursor] set];
			break;
		case 18:
			[[NSCursor verticalMovePlusCursor] set];
			break;
		default:
			[[NSCursor arrowCursor] set];
			break;
	}
}

- (void)invalidateDraggingRegion
{
	NSSize size;
	NSRect rect;
	if (pencilOn) {
		float ys = [self yScale];
	/*	rect.origin.x = draggingStartPoint.x;
		rect.origin.y = floor(draggingStartPoint.y / ys) * ys;
		rect.size.width = draggingPoint.x - draggingStartPoint.x;
		if (rect.size.width < 0) {
			rect.origin.x += rect.size.width;
			rect.size.width = -rect.size.width;
		} else if (rect.size.width == 0.0) {
			rect.size.width = [dataSource pixelsPerQuarter];
		} */
		rect.origin.x = draggingPoint.x;
		rect.origin.y = (CGFloat)(floor(draggingPoint.y / ys) * ys);
		rect.size.width = [dataSource pixelsPerQuarter];
		rect.size.height = ys;
		rect = NSInsetRect(rect, -1, -1);
	} else if (draggingMode > 0 && draggingImage != nil) {
		size = [draggingImage size];
		rect.origin.x = draggingPoint.x - size.width / 2;
		rect.origin.y = draggingPoint.y - size.height / 2;
		rect.size = size;
		rect = NSIntersectionRect(rect, [self visibleRect]);
	} else return;
	[self setNeedsDisplayInRect: rect];
}

- (NSString *)infoTextForMousePoint:(NSPoint)pt dragging:(BOOL)flag
{
	int theNote;
	char buf[8];
	float ys = [self yScale];
	theNote = (int)floor(pt.y / ys);
	MDEventNoteNumberToNoteName(theNote, buf);
	return [NSString stringWithFormat:@"%s, %@", buf, [super infoTextForMousePoint:pt dragging:flag]];
}

- (void)updateInfoTextForPoint:(NSPoint)pt
{
	//  Show the cursor info
	MDTickType theTick;
	int theNote;
	char buf[8];
	float ys = [self yScale];
	int32_t measure, beat, tick;
	theTick = [dataSource quantizedTickFromPixel:pt.x];
	[dataSource convertTick:theTick toMeasure:&measure beat:&beat andTick:&tick];
	theNote = (int)floor(pt.y / ys);
	MDEventNoteNumberToNoteName(theNote, buf);
	[dataSource setInfoText:[NSString stringWithFormat:@"%s, %d.%d.%d", buf, measure, beat, tick]];
}

- (void)doFlagsChanged: (NSEvent *)theEvent
{
	unsigned int flags = [theEvent modifierFlags];
	localGraphicTool = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
	if (![[[[self dataSource] document] myMIDISequence] isPlaying]) {
		if ((flags & NSControlKeyMask) != 0) {
			[[NSCursor speakerCursor] set];
			rubbing = YES;
			return;
		}
	}
	rubbing = NO;
	[super doFlagsChanged: theEvent];
}

- (void)doMouseMoved: (NSEvent *)theEvent
{
	int32_t track;
	int32_t pos;
	MDEvent *ep;
	int n;
	NSPoint pt;
	unsigned int flags = [theEvent modifierFlags];
	localGraphicTool = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
	if (![[[[self dataSource] document] myMIDISequence] isPlaying]) {
		if ((flags & NSControlKeyMask) != 0) {
			[[NSCursor speakerCursor] set];
			rubbing = YES;
			return;
		}
	}
	rubbing = NO;
	pt = [self convertPoint:[theEvent locationInWindow] fromView: nil];
	n = [self findNoteUnderPoint: pt track: &track position: &pos mdEvent: &ep];
	if (n > 0) {
		[self setDraggingCursor: n];
		return;
	} else if (localGraphicTool == kGraphicPencilTool) {
		[[NSCursor pencilCursor] set];
		return;
	}
	[super doMouseMoved: theEvent];
}

- (void)playMIDINote:(int)note inTrack:(int)track withVelocity: (int)velocity
{
	MyMIDISequence *seq = [[[self dataSource] document] myMIDISequence];
	int dev, ch, i, tr;
	unsigned char data[4];
	for (i = [dataSource trackCount] - 1; i >= 0; i--) {
		if (track >= 0)
			tr = track;  // i is ignored
		else {
			tr = i;
			if (![self isFocusTrack:tr])
				continue;
		}
		dev = MDPlayerGetDestinationNumberFromName([[seq deviceName: tr] UTF8String]);
		ch = [seq trackChannel: tr];
		data[0] = kMDEventSMFNoteOn | (ch & 15);
		data[1] = (note & 127);
		data[2] = (velocity & 127);
		MDPlayerSendRawMIDI(NULL, data, 3, dev, -1);
		if (track >= 0)
			break;
	}
}

- (void)invalidateRubbingTickLine
{
	NSRect rect = [self bounds];
	rect.origin.x = (CGFloat)(floor(rubbingTick * [dataSource pixelsPerTick]) - 1);
	rect.size.width = 3;
	[self setNeedsDisplayInRect:rect];
}

- (void)playNotesAtPoint:(CGFloat)xpos noteOn:(BOOL)flag
{
	int i, num, trackNum, n;
	MDTrack *track;
	MDTickType tick = (MDTickType)(floor(xpos / [dataSource pixelsPerTick] + 0.5));
	IntGroup *pset, *pset2, *pset3;
	MDPointer *pt;
	MDEvent *ep;
	num = [self visibleTrackCount];
	if (flag) {
		if (rubbingArray == nil) {
			/*  Create empty rubbingArray  */
			rubbingArray = [[NSMutableArray allocWithZone:[self zone]] initWithCapacity:num];
			for (i = 0; i < num; i++) {
				[rubbingArray addObject: [[[IntGroupObject allocWithZone: [self zone]] init] autorelease]];
			}
		} else {
			[self invalidateRubbingTickLine];
		}
		for (i = 0; i < num; i++) {
			trackNum = [self sortedTrackNumberAtIndex:i];
			if (![self isFocusTrack:trackNum])
				continue;
			pset = [[rubbingArray objectAtIndex:i] pointSet];
			track = [[[dataSource document] myMIDISequence] getTrackAtIndex: trackNum];
			pset2 = MDTrackSearchEventsWithDurationCrossingTick(track, tick);
			pt = MDPointerNew(track);
			pset3 = IntGroupNew();
			IntGroupDifference(pset, pset2, pset3);  /*  Notes to be turned off  */
			n = -1;
			while ((ep = MDPointerForwardWithPointSet(pt, pset3, &n)) != NULL) {
				[self playMIDINote:MDGetCode(ep) inTrack:trackNum withVelocity:0];
			}
			IntGroupDifference(pset, pset3, pset);  /*  Notes that are on at present  */
			IntGroupDifference(pset2, pset, pset3);  /*  Notes to be turned on  */
			MDPointerSetPosition(pt, -1);
			n = -1;
			while ((ep = MDPointerForwardWithPointSet(pt, pset3, &n)) != NULL) {
				[self playMIDINote:MDGetCode(ep) inTrack:trackNum withVelocity:MDGetData1(ep)];
			}
			IntGroupCopy(pset, pset2);
			IntGroupRelease(pset2);
			IntGroupRelease(pset3);
			MDPointerRelease(pt);
		}
		rubbingTick = tick;
		[self invalidateRubbingTickLine];
	} else {
		/*  Send note off and dispose rubbingArray  */
		if (rubbingArray != nil) {
			[self invalidateRubbingTickLine];
			for (i = 0; i < num; i++) {
				trackNum = [self sortedTrackNumberAtIndex:i];
				if (![self isFocusTrack:trackNum])
					continue;
				track = [[[dataSource document] myMIDISequence] getTrackAtIndex: trackNum];
				pset = [[rubbingArray objectAtIndex:i] pointSet];
				pt = MDPointerNew(track);
				n = -1;
				while ((ep = MDPointerForwardWithPointSet(pt, pset, &n)) != NULL) {
					[self playMIDINote:MDGetCode(ep) inTrack:trackNum withVelocity:0];
				}
				MDPointerRelease(pt);
			}
			[rubbingArray release];
			rubbingArray = nil;
		}
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

- (void)doMouseDown: (NSEvent *)theEvent
{
//	int track;
//	int32_t pos;
	MDEvent *ep;
//	NSSize size;
//	BOOL shiftDown;
	
	float ys = [self yScale];
	NSPoint pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
//	shiftDown = (([theEvent modifierFlags] & NSShiftKeyMask) != 0);
	
	draggingMode = [self findNoteUnderPoint: pt track: &mouseDownTrack position: &mouseDownPos mdEvent: &ep];
	if (rubbing) {
		[self playNotesAtPoint:pt.x noteOn:YES];
		return;
	}
	pt.x = [dataSource quantizedPixelFromPixel: pt.x];
	draggingStartPoint = draggingPoint = pt;
	if (draggingMode > 0) {
		playingTrack = mouseDownTrack;
		playingNote = MDGetCode(ep);
		playingVelocity = MDGetNoteOnVelocity(ep);
		[self playMIDINote:playingNote inTrack:playingTrack withVelocity:playingVelocity];
		return;
	} else if (localGraphicTool == kGraphicPencilTool) {
		pencilOn = YES;
		[self invalidateDraggingRegion];
		[self displayIfNeeded];
		playingTrack = -1;  //  All editable tracks
		playingNote = (int)(floor(pt.y / ys) + 0.5);
		playingVelocity = 64;
		[self playMIDINote:playingNote inTrack:playingTrack withVelocity:playingVelocity];
		return;
	} else {
		[super doMouseDown: theEvent];
		playingNote = -1;
	}
}

- (void)doMouseDragged: (NSEvent *)theEvent
{
	int i;
	id clientView;
	NSPoint pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
	float ys = [self yScale];
	if (rubbing) {
		[self playNotesAtPoint:pt.x noteOn:YES];
		return;
	}
	pt.x = [dataSource quantizedPixelFromPixel: pt.x];
	if (draggingMode > 0) {

		if (draggingMode == 1 || draggingMode == 3)
			pt.y = draggingStartPoint.y;
		else if (draggingMode == 2) {
			pt.x = draggingStartPoint.x;
			pt.y = (CGFloat)(floor((pt.y - draggingStartPoint.y) / ys + 0.5) * ys + draggingStartPoint.y);
		}
				
		if (draggingImage == nil) {
			//  Create an NSImage for dragging
			NSRect rect, rect2, bounds;
			NSSize size;
			float pixelQuantum;
			NSImage *image;
			MyDocument *document = [dataSource document];
			BOOL shiftDown = (([theEvent modifierFlags] & NSShiftKeyMask) != 0);
			BOOL optionDown = (([theEvent modifierFlags] & NSAlternateKeyMask) != 0);
			if (![document isSelectedAtPosition: mouseDownPos inTrack: mouseDownTrack]) {
			//	int i, n;
				if (!shiftDown) {
				//	for (i = 0; (n = [self sortedTrackNumberAtIndex: i]) >= 0; i++)
				//		[document unselectAllEventsInTrack: n sender: self];
					[document unselectAllEventsInAllTracks: self];
				}
				[document selectEventAtPosition: mouseDownPos inTrack: mouseDownTrack sender: self];
			}
		/*	else {
				if (shiftDown) {
					[document unselectEventAtPosition: pos inTrack: track sender: self];
					draggingMode = 0;
					return;
				}
			} */
			size = [self visibleRect].size;
			rect.origin.x = pt.x - size.width;
			rect.origin.y = pt.y - size.height;
			rect.size.width = size.width * 2;
			rect.size.height = size.height * 2;
			image = [[NSImage allocWithZone: [self zone]] initWithSize: rect.size];
			[image lockFocus];
			[self drawNotesInRect: rect selectionOnly: YES offset: NSMakePoint(-rect.origin.x, -rect.origin.y) addDuration: 0];
			[image unlockFocus];
			draggingImage = image;
			[self setDraggingCursor: draggingMode + (draggingMode != 3 && optionDown ? 16 : 0)];
			[self invalidateDraggingRegion];
			[self displayIfNeeded];
			//  Calculate limit rectangle for the dragging point
			bounds = [self bounds];
			rect2 = [self boundRectForSelection];
			limitRect= NSMakeRect(
				pt.x - (rect2.origin.x - bounds.origin.x),
				pt.y - (rect2.origin.y - bounds.origin.y),
				bounds.size.width - rect2.size.width,
				bounds.size.height - rect2.size.height);
			pixelQuantum = [dataSource pixelQuantum];
			limitRect.origin.x = [dataSource quantizedPixelFromPixel: limitRect.origin.x];
			if (limitRect.origin.x < 0.0)
				limitRect.origin.x += pixelQuantum;
			limitRect.size.width = (CGFloat)(floor(limitRect.size.width / pixelQuantum) * pixelQuantum);
			if (limitRect.size.width + limitRect.origin.x > bounds.origin.x + bounds.size.width)
				limitRect.size.width -= pixelQuantum;
			if (draggingMode == 1) {
				//  Notify stripChartViews to scroll
				for (i = 0; (clientView = [dataSource clientViewAtIndex:i]) != nil; i++) {
					if ([clientView isKindOfClass:[StripChartView class]]) {
						[clientView startExternalDraggingAtPoint:draggingStartPoint mode:draggingMode];
					}
				}
			}
		}
	
		//  Support autoscroll (cf. GraphicClientView.mouseDragged)
	/*	if (autoscrollTimer != nil) {
			[autoscrollTimer invalidate];
			[autoscrollTimer release];
			autoscrollTimer = nil;
		}
		pt = [self convertPoint: pt toView: nil];
		[self invalidateDraggingRegion];
		if ([self autoscroll: [theEvent mouseEventWithLocation: pt]])
			autoscrollTimer = [[NSTimer scheduledTimerWithTimeInterval: 0.2 target: self selector:@selector(autoscrollTimerCallback:) userInfo: theEvent repeats: NO] retain];
		pt = [self convertPoint: pt fromView: nil]; */

		if (draggingMode != 3) {
			if (pt.x < limitRect.origin.x)
				pt.x = limitRect.origin.x;
			else if (pt.x > limitRect.origin.x + limitRect.size.width)
				pt.x = limitRect.origin.x + limitRect.size.width;
			if (pt.y < limitRect.origin.y)
				pt.y = limitRect.origin.y;
			else if (pt.y > limitRect.origin.y + limitRect.size.height)
				pt.y = limitRect.origin.y + limitRect.size.height;
		}
		draggingPoint = pt;
		[self invalidateDraggingRegion];
		[self displayIfNeeded];
		if (draggingMode == 1) {
			//  Notify stripChartViews to scroll
			for (i = 0; (clientView = [dataSource clientViewAtIndex:i]) != nil; i++) {
				if ([clientView isKindOfClass:[StripChartView class]]) {
					[clientView setExternalDraggingPoint:pt];
				}
			}
		}
	} else if (pencilOn) {
		[self invalidateDraggingRegion];
		draggingPoint = pt;
		[self invalidateDraggingRegion];
		[self displayIfNeeded];
	} else {
		[super doMouseDragged: theEvent];
		return;
	}
	if (playingNote >= 0) {
		int note = (int)(floor(draggingPoint.y / ys) + 0.5);
		if (note != playingNote) {
			[self playMIDINote:playingNote inTrack:playingTrack withVelocity:0];
			playingNote = note;
			[self playMIDINote:playingNote inTrack:playingTrack withVelocity:playingVelocity];
		}
	}	
}

- (void)doMouseUp: (NSEvent *)theEvent
{
	int i, trackNo;
	float ppt, ys;
	MDTickType minTick, maxTick;
	BOOL shiftDown, optionDown;
	NSRect bounds;
	MyDocument *document = (MyDocument *)[dataSource document];

	if (playingNote >= 0) {
		[self playMIDINote:playingNote inTrack:playingTrack withVelocity:0];
		playingNote = playingVelocity = playingTrack = -1;
	}

	if (rubbing) {
		[self playNotesAtPoint:0.0f noteOn:NO];  /*  0.0 is dummy; all notes off */
		return;
	}

	/*  Mouse down on a note  */
	if (draggingMode > 0) {
		NSPoint pt;
		MDTickType deltaTick;
		int deltaNote;
		if (draggingImage == nil) {
			/*  No dragging --- just change selection  */
			shiftDown = (([theEvent modifierFlags] & NSShiftKeyMask) != 0);
			if (![document isSelectedAtPosition: mouseDownPos inTrack: mouseDownTrack]) {
			//	int i, n;
				if (!shiftDown) {
				//	for (i = 0; (n = [self sortedTrackNumberAtIndex: i]) >= 0; i++)
				//		[document unselectAllEventsInTrack: n sender: self];
					[document unselectAllEventsInAllTracks: self];
				}
				[document selectEventAtPosition: mouseDownPos inTrack: mouseDownTrack sender: self];
			} else {
				if (shiftDown) {
					[document unselectEventAtPosition: mouseDownPos inTrack: mouseDownTrack sender: self];
				}
			}
			draggingMode = 0;
			[self displayIfNeeded];
			return;
		}

		[self invalidateDraggingRegion];
		pt.x = draggingPoint.x - draggingStartPoint.x;
		pt.y = draggingPoint.y - draggingStartPoint.y;
		deltaTick = (MDTickType)(floor(pt.x / [dataSource pixelsPerTick] + 0.5));
		deltaNote = (int)floor(pt.y / [self yScale] + 0.5);
		optionDown = (([theEvent modifierFlags] & NSAlternateKeyMask) != 0);
		if (draggingMode == 1 || draggingMode == 2) {
			[dataSource dragNotesByTick: deltaTick andNote: deltaNote sender: self optionFlag: optionDown];
		} else if (draggingMode == 3) {
			[dataSource dragDurationByTick: deltaTick sender: self];
		}
		[draggingImage release];
		draggingImage = nil;
		if (draggingMode == 1) {
			//  Notify stripChartViews
			int i;
			id clientView;
			for (i = 0; (clientView = [dataSource clientViewAtIndex:i]) != nil; i++) {
				if ([clientView isKindOfClass:[StripChartView class]]) {
					[clientView endExternalDragging];
				}
			}
		}
		draggingMode = 0;
	//	[self displayIfNeeded];
		return;
	}

	/*  Pencil edit  */
	if (pencilOn) {
		int keyCode;
		float x1;
		[self invalidateDraggingRegion];

		ppt = [dataSource pixelsPerTick];
		ys = [self yScale];
	/*	x1 = draggingStartPoint.x;
		x2 = draggingPoint.x;
		if (x2 < x1) {
			x2 = x1;
			x1 = draggingPoint.x;
		} else if (x2 == x1) {
			x2 = x1 + [dataSource pixelsPerQuarter];
		}
		minTick = (MDTickType)(x1 / ppt);
		maxTick = (MDTickType)(x2 / ppt);
		//  This should be double checked, because it is possible that x2 > x1 but maxTick == minTick
		if (minTick == maxTick)
			maxTick = minTick + [document timebase];
		keyCode = (int)(floor(draggingStartPoint.y / ys)); */
		x1 = draggingPoint.x;
		minTick = (MDTickType)(x1 / ppt);
		maxTick = minTick + [document timebase];
		if (minTick == maxTick)
			maxTick = minTick + 1;
		keyCode = (int)(floor(draggingPoint.y / ys));
		if (keyCode < 0)
			keyCode = 0;
		if (keyCode > 127)
			keyCode = 127;
		for (i = 0; (trackNo = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
			MDEventObject *newEvent;
			MDEvent *ep;
			if (![self isFocusTrack:trackNo])
				continue;
			newEvent = [[[MDEventObject allocWithZone: [self zone]] init] autorelease];
			ep = &(newEvent->event);
			MDSetTick(ep, minTick);
			MDSetKind(ep, kMDEventNote);
			MDSetCode(ep, keyCode);
			MDSetNoteOnVelocity(ep, 64);
			MDSetNoteOffVelocity(ep, 64);
			MDSetDuration(ep, maxTick - minTick);
			[document insertEvent: newEvent toTrack: trackNo];
		}
		
		pencilOn = NO;
		return;
	}
	
	/*  Box selection  */
	if (isDragging && !isLoupeDragging) {
		shiftDown = (([theEvent modifierFlags] & NSShiftKeyMask) != 0);
		bounds = [[self selectionPath] bounds];
		ppt = [dataSource pixelsPerTick];
		ys = [self yScale];
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
				if (MDGetKind(ep) != kMDEventNote)
					continue;
				point.x = (CGFloat)(floor(MDGetTick(ep) * ppt));
				point.y = (CGFloat)(floor(MDGetCode(ep) * ys + 0.5) + 0.5 * ys);
				if ([self isPointInSelectRegion: point]) {
					if (IntGroupAdd(pset, MDPointerGetPosition(pt), 1) != kMDNoError)
						break;
				}
			}
			obj = [[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: pset];
			if (shiftDown) {
				[document toggleSelection: obj inTrack: trackNo sender: self];
			} else {
				[document setSelection: obj inTrack: trackNo sender: self];
			}
			[obj release];
			IntGroupRelease(pset);
			MDPointerRelease(pt);
		}
		return;

	} else {
		/*  LoupeDragging, etc.  */
		[super doMouseUp: theEvent];
		return;
	}
}

//  Called from -[GraphicWindowController mouseExited:]
- (void)mouseExited: (NSEvent *)theEvent
{
	
}

#if 0
- (void)mouseUp: (NSEvent *)theEvent
{
	NSPoint pt;
	MDTickType deltaTick;
	int deltaNote;
	if (draggingMode > 0) {
		[self invalidateDraggingRegion];
		pt.x = draggingPoint.x - draggingStartPoint.x;
		pt.y = draggingPoint.y - draggingStartPoint.y;
		deltaTick = floor(pt.x / [dataSource pixelsPerTick] + 0.5);
		deltaNote = (int)floor(pt.y / [self yScale] + 0.5);
		if (draggingMode == 1 || draggingMode == 2) {
			[dataSource dragNotesByTick: deltaTick andNote: deltaNote sender: self];
		} else if (draggingMode == 3) {
			[dataSource dragDurationByTick: deltaTick sender: self];
		}
		[draggingImage release];
		draggingImage = nil;
		draggingMode = 0;
		[self displayIfNeeded];
	} else [super mouseUp: theEvent];
}
#endif

@end
