/*
    PianoRollView.m
*/
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

static float sLineDash1[] = {6.0, 2.0};
static float sLineDash2[] = {2.0, 6.0};
static float sDashWidth = 8.0;

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
	pt1.y = floor(aRect.origin.y / sDashWidth) * sDashWidth;
	pt2.y = ceil((aRect.origin.y + aRect.size.height) / sDashWidth) * sDashWidth;
	lines = [[NSBezierPath allocWithZone: [self zone]] init];
	subLines = [[NSBezierPath allocWithZone: [self zone]] init];
	originx = aRect.origin.x;
	if (originx == 0.0)
		originx = 1.0;	/*  Avoid drawing line at tick = 0  */
	pt2.x = 0.0;
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
		numLines = floor((nextSigTick - sigTick) * ppt / interval) + 1;
		i = (startx >= originx ? 0 : floor((originx - startx) / interval));
		for ( ; i < numLines; i++) {
			pt1.x = floor(startx + i * interval) + 0.5;
			if (pt1.x >= originx && pt1.x <= aRect.origin.x + aRect.size.width) {
				if (pt1.x > limitx && pt2.x <= limitx) {
					/*  Draw the lines and set the color to gray  */
					[lines setLineDash: sLineDash1 count: 2 phase: 0.0];
					[subLines setLineDash: sLineDash2 count: 2 phase: 0.0];
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
	[lines setLineDash: sLineDash1 count: 2 phase: 0.0];
	[subLines setLineDash: sLineDash2 count: 2 phase: 0.0];
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
		[NSBezierPath setDefaultLineWidth: 2.0];
		pt1.x = pt2.x += 3.0;
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
	startx = sDashWidth * floor(aRect.origin.x / sDashWidth);
	endx = sDashWidth * ceil((aRect.origin.x + aRect.size.width) / sDashWidth + 1.0);
	ys = [self yScale];
	for (i = 0; i < 2; i++) {
		if (i == 0) {
			if (limitx >= aRect.origin.x + aRect.size.width)
				continue;
			[[NSColor grayColor] set];
			pt1.x = sDashWidth * floor(limitx / sDashWidth);
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
			pt1.y = floor((n + 0.5) * ys) + 0.5;
			pt2.y = pt1.y;
			[path moveToPoint: pt1];
			[path lineToPoint: pt2];
		}
		[staves setLineDash: sLineDash1 count: 2 phase: 0.0];
		[subStaves setLineDash: sLineDash2 count: 2 phase: 0.0];
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
	MDPointSet *pset;
//	MDPointer *pt;
//	MDEvent *ep;
	[cacheArray release];
	num = [dataSource visibleTrackCount];
	cacheArray = [[NSMutableArray allocWithZone: [self zone]] initWithCapacity: num + 1];
	cacheTick = tick;
	for (i = 0; i <= num; i++) {
		if (i == num) {
			track = [[[dataSource document] myMIDISequence] recordTrack];
			if (track == NULL)
				break;
			trackNum = -1;
		} else {
			trackNum = [dataSource sortedTrackNumberAtIndex: i];
			track = [[[dataSource document] myMIDISequence] getTrackAtIndex: trackNum];
		}
	#if 1
		pset = MDTrackSearchEventsWithDurationCrossingTick(track, tick);
//		fprintf(stderr, "%s[%d]: track %p tick %ld, ", __FILE__, __LINE__, track, (long)tick); MDPointSetDump(pset);
	#else
		pset = MDPointSetNew();
		if (pset != NULL) {
			pt = MDPointerNew(track);
			if (pt != NULL) {
				MDPointerJumpToTick(pt, tick);
				while ((ep = MDPointerBackward(pt)) != NULL) {
					if (MDGetKind(ep) == kMDEventNote && MDGetTick(ep) + MDGetDuration(ep) >= tick)
						MDPointSetAdd(pset, MDPointerGetPosition(pt), 1);
				}
				MDPointerRelease(pt);
			}
		}
	//	fprintf(stderr, "%s[%d]: ", __FILE__, __LINE__);
	//	MDPointSetDump(pset);
	#endif
		[cacheArray addObject: [[[MDPointSetObject allocWithZone: [self zone]] initWithMDPointSet: pset] autorelease]];
		if (pset != NULL)
			MDPointSetRelease(pset);
	}
}

static void
appendNotePath(NSBezierPath *path, float x1, float x2, float y, float ys)
{
	if (x2 - x1 <= ys) {
		[path appendBezierPathWithOvalInRect: NSMakeRect(x1, y, x2 - x1, ys)];
	} else {
		float ys2 = ys * 0.5;
		[path moveToPoint: NSMakePoint(x1 + ys2, y)];
		[path lineToPoint: NSMakePoint(x2 - ys2, y)];
		[path appendBezierPathWithArcWithCenter: NSMakePoint(x2 - ys2, y + ys2) radius: ys2 startAngle: -90.0 endAngle: 90.0];
		[path lineToPoint: NSMakePoint(x1 + ys2, y + ys)];
		[path appendBezierPathWithArcWithCenter: NSMakePoint(x1 + ys2, y + ys2) radius: ys2 startAngle: 90.0 endAngle: -90.0];
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
	static float sDash[] = { 2, 2 };
	BOOL isDraggingImage = NO;
	
	if (draggingMode > 0 && draggingMode < 3 && draggingImage != nil)
		isDraggingImage = YES;

	if (cacheArray == nil || originTick != cacheTick)
		[self cacheNotesBeforeTick: originTick];
	num = [dataSource visibleTrackCount];
	normalPath = [[NSBezierPath allocWithZone: [self zone]] init];
	selectedPath = [[NSBezierPath allocWithZone: [self zone]] init];
	if (isDraggingImage)
		[selectedPath setLineDash:sDash count:2 phase:0.0];
	startTick = (MDTickType)(aRect.origin.x / ppt);
	endTick = (MDTickType)((aRect.origin.x + aRect.size.width) / ppt);
//	NSLog(@"drawNotesInRect: startTick %ld endTick %ld", (long)startTick, (long)endTick);
	startNote = floor(aRect.origin.y / ys);
	endNote = ceil((aRect.origin.y + aRect.size.height) / ys);
	for (i = num; i >= 0; i--) {
		int trackNum;
		long n;
		MDTrack *track;
		MDPointSet *pset;
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
			trackNum = [dataSource sortedTrackNumberAtIndex: i];
			track = [[document myMIDISequence] getTrackAtIndex: trackNum];
			if (track == NULL)
				continue;
			isFocus = [dataSource isFocusTrack: trackNum];
		}
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
			//	fprintf(stderr, "%s[%d]: ep=%p pos=%ld n=%ld\n", __FILE__, __LINE__, ep, (long)MDPointerGetPosition(pt), (long)n);
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
			x1 = floor(MDGetTick(ep) * ppt);
			x2 = floor(tick2 * ppt);
			y = floor(note * ys + 0.5);
		//	if (isDragging && !pencilOn && !isLoupeDragging && draggingMode == 0 && isFocus) {
			if (isFocus && !isLoupeDragging && selectionPath != nil) {
				/*  Change selection by dragging  */
				if ([self isPointInSelectRegion: NSMakePoint(x1, y + 0.5 * ys)]) {
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
			y = floor(draggingPoint.y / ys) * ys;
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

- (void)drawRect: (NSRect)aRect
{
	MDTickType deltaDuration;
	if (draggingMode == 3)
		deltaDuration = floor((MDTickType)((draggingPoint.x - draggingStartPoint.x) / [dataSource pixelsPerTick]) + 0.5);
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
				[draggingImage dissolveToPoint: NSMakePoint(draggingPoint.x - size.width / 2, draggingPoint.y - size.height / 2) fraction: 0.8];
			}
		}
	}
	[self drawSelectRegion];
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
	y0 = (floor(rect.origin.y / ys)) * ys - 1;
	y1 = (ceil((rect.origin.y + rect.size.height) / ys) + 1.0) * ys + 1;
	rect.origin.y = y0;
	rect.size.height = y1 - y0;
	visibleRect = [self visibleRect];
	rect.origin.x = visibleRect.origin.x;
	rect.size.width = visibleRect.size.width;
	return rect;
}

/*  Returns 0-3; 0: no note, 1: left 1/3 of a note, 2: middle 1/3 of a note,
    3: right 1/3 of a note  */
- (int)findNoteUnderPoint: (NSPoint)aPoint track: (long *)outTrack position: (long *)outPosition mdEvent: (MDEvent **)outEvent
{
	int num, i;
	NSRect rect = [self visibleRect];
	float ppt = [dataSource pixelsPerTick];
	float ys = [self yScale];
	MyDocument *document = (MyDocument *)[dataSource document];
	MDTickType originTick = (MDTickType)(rect.origin.x / ppt);
	MDTickType theTick;
	int theNote;

	num = [dataSource visibleTrackCount];
	theTick = (MDTickType)(aPoint.x / ppt);
	theNote = floor(aPoint.y / ys);
	for (i = 0; i < num; i++) {
		int trackNum;
		long n;
		MDTrack *track;
		MDPointSet *pset;
		MDPointer *pt;
		MDEvent *ep;
		trackNum = [dataSource sortedTrackNumberAtIndex: i];
		if (![dataSource isFocusTrack: trackNum])
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
					MDPointerSetPositionWithPointSet(pt, pset, -1, &n);
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
			if (tick2 < MDGetDuration(ep) / 3)
				return 1;
			else if (tick2 < MDGetDuration(ep) * 2 / 3)
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
	for (i = 0; (n = [dataSource sortedTrackNumberAtIndex: i]) >= 0; i++) {
		long index;
		MDPointer *pt;
		MDEvent *ep;
		MDTrack *track = [[document myMIDISequence] getTrackAtIndex: n];
		MDPointSet *pset = [[document selectionOfTrack: n] pointSet];
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
		rect.origin.y = floor(draggingPoint.y / ys) * ys;
		rect.size.width = [dataSource pixelsPerQuarter];
		rect.size.height = ys;
		rect = NSInsetRect(rect, -1, -1);
	} else if (draggingMode > 0 && draggingImage != nil) {
		size = [draggingImage size];
		rect.origin.x = draggingPoint.x - size.width / 2;
		rect.origin.y = draggingPoint.y - size.height / 2;
		rect.size = size;
		rect = NSIntersectionRect(rect, [self visibleRect]);
	}
	[self setNeedsDisplayInRect: rect];
}

- (void)doMouseMoved: (NSEvent *)theEvent
{
	long track;
	long pos;
	MDEvent *ep;
	int n, tool;
	NSPoint pt = [theEvent locationInWindow];
	pt = [self convertPoint: pt fromView: nil];
	n = [self findNoteUnderPoint: pt track: &track position: &pos mdEvent: &ep];
	tool = [[self dataSource] graphicTool];
	if (n > 0)
		[self setDraggingCursor: n];
	else if (tool == kGraphicPencilTool || (tool == kGraphicRectangleSelectTool && ([theEvent modifierFlags] & NSCommandKeyMask) != 0))
		[[NSCursor pencilCursor] set];
	else [super doMouseMoved: theEvent];
}

- (void)playMIDINoteWithVelocity: (int)velocity
{
	MyMIDISequence *seq = [[[self dataSource] document] myMIDISequence];
	int track, dev, ch, i;
	unsigned char data[4];
	for (i = [dataSource trackCount] - 1; i >= 0; i--) {
		if (playingTrack >= 0)
			track = playingTrack;  // i is ignored
		else {
			track = i;
			if (![dataSource isFocusTrack: track])
				continue;
		}
		dev = MDPlayerGetDestinationNumberFromName([[seq deviceName: track] UTF8String]);
		ch = [seq trackChannel: track];
		data[0] = kMDEventSMFNoteOn | (ch & 15);
		data[1] = (playingNote & 127);
		data[2] = (velocity & 127);
		MDPlayerSendRawMIDI(NULL, data, 3, dev, -1);
		if (playingTrack >= 0)
			break;
	}
}

- (void)doMouseDown: (NSEvent *)theEvent
{
//	int track;
//	long pos;
	MDEvent *ep;
//	NSSize size;
//	BOOL shiftDown;
	
	float ys = [self yScale];
	NSPoint pt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
//	shiftDown = (([theEvent modifierFlags] & NSShiftKeyMask) != 0);
	
	if (localGraphicTool == kGraphicRectangleSelectTool && ([theEvent modifierFlags] & NSCommandKeyMask) != 0)
		localGraphicTool = kGraphicPencilTool;

	draggingMode = [self findNoteUnderPoint: pt track: &mouseDownTrack position: &mouseDownPos mdEvent: &ep];
	pt.x = [dataSource quantizedPixelFromPixel: pt.x];
	draggingStartPoint = draggingPoint = pt;
	if (draggingMode > 0) {
		playingTrack = mouseDownTrack;
		playingNote = MDGetCode(ep);
		playingVelocity = MDGetNoteOnVelocity(ep);
		[self playMIDINoteWithVelocity: playingVelocity];
		return;
	} else if (localGraphicTool == kGraphicPencilTool) {
		pencilOn = YES;
		[self invalidateDraggingRegion];
		[self displayIfNeeded];
		playingTrack = -1;  //  All editable tracks
		playingNote = (int)(floor(pt.y / ys) + 0.5);
		playingVelocity = 64;
		[self playMIDINoteWithVelocity: playingVelocity];
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
	pt.x = [dataSource quantizedPixelFromPixel: pt.x];
	if (draggingMode > 0) {

		if (draggingMode == 1 || draggingMode == 3)
			pt.y = draggingStartPoint.y;
		else if (draggingMode == 2) {
			pt.x = draggingStartPoint.x;
			pt.y = floor((pt.y - draggingStartPoint.y) / ys + 0.5) * ys + draggingStartPoint.y;
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
				//	for (i = 0; (n = [dataSource sortedTrackNumberAtIndex: i]) >= 0; i++)
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
			limitRect.size.width = floor(limitRect.size.width / pixelQuantum) * pixelQuantum;
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
			[self playMIDINoteWithVelocity: 0];
			playingNote = note;
			[self playMIDINoteWithVelocity: playingVelocity];
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
		[self playMIDINoteWithVelocity: 0];
		playingNote = playingVelocity = playingTrack = -1;
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
				//	for (i = 0; (n = [dataSource sortedTrackNumberAtIndex: i]) >= 0; i++)
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
		deltaTick = floor(pt.x / [dataSource pixelsPerTick] + 0.5);
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
		for (i = 0; (trackNo = [dataSource sortedTrackNumberAtIndex: i]) >= 0; i++) {
			MDEventObject *newEvent;
			MDEvent *ep;
			if (![dataSource isFocusTrack: trackNo])
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
		for (i = 0; (trackNo = [dataSource sortedTrackNumberAtIndex: i]) >= 0; i++) {
			MDTrack *track;
			MDPointer *pt;
			MDEvent *ep;
			MDPointSet *pset;
			MDSelectionObject *obj;
			if (![dataSource isFocusTrack: trackNo])
				continue;
			track = [[document myMIDISequence] getTrackAtIndex: trackNo];
			if (track == NULL)
				continue;
			pt = MDPointerNew(track);
			if (pt == NULL)
				break;
			pset = MDPointSetNew();
			if (pset == NULL)
				break;
			MDPointerJumpToTick(pt, minTick);
			MDPointerBackward(pt);
			while ((ep = MDPointerForward(pt)) != NULL && MDGetTick(ep) < maxTick) {
				NSPoint point;
				if (MDGetKind(ep) != kMDEventNote)
					continue;
				point.x = floor(MDGetTick(ep) * ppt);
				point.y = floor(MDGetCode(ep) * ys + 0.5) + 0.5 * ys;
				if ([self isPointInSelectRegion: point]) {
					if (MDPointSetAdd(pset, MDPointerGetPosition(pt), 1) != kMDNoError)
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
			MDPointSetRelease(pset);
			MDPointerRelease(pt);
		}
		return;

	} else {
		/*  LoupeDragging, etc.  */
		[super doMouseUp: theEvent];
		return;
	}
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
