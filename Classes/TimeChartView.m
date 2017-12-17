//
//  TimeChartView.m
//  Created by Toshi Nagata on Sat Jan 25 2003.
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

#import "TimeChartView.h"
#import "GraphicWindowController.h"
#import "MyDocument.h"
#import "MyAppController.h"
#import "MyMIDISequence.h"
#import "MDObjects.h"
#import "NSStringAdditions.h"
#import <math.h>
#import "MDHeaders.h"
#import "NSCursorAdditions.h"
#import "PlayingViewController.h"

typedef struct TimeScalingRecord {
	MDTickType startTick;  /*  Start tick of the time region to be scaled   */
	MDTickType endTick;    /*  End tick of the time region to be scaled  */
	MDTickType newEndTick; /*  End tick after scaling the time region  */
	int ntracks;           /*  Number of editable tracks  */
	int *trackNums;        /*  Track numbers  */
	int32_t *startPos;        /*  Start positions for each track to modify ticks  */
	MDTickType **originalTicks;  /*  Arrays of original ticks for each track  */
} TimeScalingRecord;

@implementation TimeChartView

//- (BOOL)willChangeSelectionOnMouseDown
//{
//    return NO;
//}

+ (float)minHeight
{
	return 36.0f;
}

- (int)clientViewType
{
	return kGraphicTimeChartViewType;
}

//- (id)initWithFrame: (NSRect)rect
//{
//    self = [super initWithFrame: rect];
//    if (self) {
//		selectMode = kGraphicClientIbeamMode;
//    }
//    return self;
//}

- (void)drawContentsInRect: (NSRect)aRect
{
	float ppt;
	MDTickType beginTick, endTick;
	float originx;
	float limitx;
    float basey, maxLabelWidth;
	NSPoint pt1, pt2;
    NSRect visibleRect = [self visibleRect];
    float editingRangeStartX, editingRangeEndX;

    basey = visibleRect.origin.y + 0.5f;
	ppt = [dataSource pixelsPerTick];
	limitx = [dataSource sequenceDurationInQuarter] * [dataSource pixelsPerQuarter];

	[self paintEditingRange: aRect startX: &editingRangeStartX endX: &editingRangeEndX];
	
    /*  Draw horizontal axis  */
    [NSBezierPath strokeLineFromPoint: NSMakePoint(aRect.origin.x, basey) toPoint: NSMakePoint(aRect.origin.x + aRect.size.width, basey)];
    
    /*  Draw ticks, labels, and time signatures  */
    maxLabelWidth = [@"0000:00:0000" sizeWithAttributes: nil].width;
    originx = aRect.origin.x - maxLabelWidth;
    if (originx < 0.0f)
        originx = 0.0f;
	beginTick = originx / ppt;
	endTick = (aRect.origin.x + aRect.size.width) / ppt + 1;
	while (beginTick < endTick) {
		int mediumCount, majorCount, i, numLines;
        int sigNumerator, sigDenominator;
		MDEvent *sig1, *sig2;
		MDTickType sigTick, nextSigTick;
		float interval, startx;
        float widthPerBeat, widthPerMeasure;
		[dataSource verticalLinesFromTick: beginTick timeSignature: &sig1 nextTimeSignature: &sig2 lineIntervalInPixels: &interval mediumCount: &mediumCount majorCount: &majorCount];
		sigTick = (sig1 == NULL ? 0 : MDGetTick(sig1));
		nextSigTick = (sig2 == NULL ? kMDMaxTick : MDGetTick(sig2));
		if (nextSigTick > endTick)
			nextSigTick = endTick;
		startx = sigTick * ppt;
        sigDenominator = (sig1 == NULL ? 4 : (1 << (int)(MDGetMetaDataPtr(sig1)[1])));
        sigNumerator = (sig1 == NULL ? 4 : MDGetMetaDataPtr(sig1)[0]);
        if (sigNumerator == 0)
            sigNumerator = 4;
        [[NSString stringWithFormat: @"%d/%d", sigNumerator, sigDenominator] drawAtPoint: NSMakePoint(startx, basey + 22.0f) withAttributes: nil clippingRect: aRect];
        numLines = (int)floor((nextSigTick - sigTick) * ppt / interval) + 1;
		i = (startx >= originx ? 0 : (int)floor((originx - startx) / interval));
		[[NSColor blackColor] set];
		for ( ; i < numLines; i++) {
            pt1 = NSMakePoint((CGFloat)(floor(startx + i * interval) + 0.5), basey);
            pt2.x = pt1.x;
			if (pt1.x > limitx)
				[[NSColor grayColor] set];
            if (i % majorCount == 0) {
                /*  Draw label  */
                NSString *label;
                int32_t n1, n2, n3;
                [dataSource convertTick: (MDTickType)floor((startx + i * interval) / ppt + 0.5) toMeasure: &n1 beat: &n2 andTick: &n3];
                widthPerBeat = [(MyDocument *)[dataSource document] timebase] * ppt * 4 / sigDenominator;
                widthPerMeasure = widthPerBeat * sigNumerator;
                if (interval * majorCount >= widthPerMeasure) {
                    label = [NSString stringWithFormat: @"%d", (int)n1];
                } else if (interval * majorCount >= widthPerBeat) {
                    //  The major tick interval >= beat
                    label = [NSString stringWithFormat: @"%d:%d", (int)n1, (int)n2];
                } else {
                    //  The major tick interval < beat
                    label = [NSString stringWithFormat: @"%d:%d:%d", (int)n1, (int)n2, (int)n3];
                }
                [label drawAtPoint: NSMakePoint((CGFloat)floor(pt1.x), (CGFloat)floor(pt1.y + 10.0)) withAttributes: nil clippingRect: aRect];
            }
			if (pt1.x >= aRect.origin.x && pt1.x <= aRect.origin.x + aRect.size.width) {
                /*  Draw axis marks */
				if (i % majorCount == 0) {
                    pt2.y = pt1.y + 9.0f;
                } else if (i % mediumCount == 0)
                    pt2.y = pt1.y + 6.0f;
                else pt2.y = pt1.y + 3.0f;
                [NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
            }
		}
		beginTick = nextSigTick;
	}
	/*  Draw selection range symbols  */
	[[NSColor blackColor] set];
	if (editingRangeStartX >= 0) {
		static NSImage *sStartEditingImage = nil;
		static NSImage *sEndEditingImage = nil;
		if (sStartEditingImage == nil) {
			sStartEditingImage = [[NSImage allocWithZone: [self zone]] initWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"StartEditingRange.png" ofType: nil]];
		}
		if (sEndEditingImage == nil) {
			sEndEditingImage = [[NSImage allocWithZone: [self zone]] initWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"EndEditingRange.png" ofType: nil]];
		}
		pt1.x = editingRangeStartX - 5.0f;
		pt1.y = visibleRect.origin.y + 1.0f;
		if (pt1.x >= aRect.origin.x && pt1.x < aRect.origin.x + aRect.size.width) {
            [sStartEditingImage drawAtPoint: pt1 fromRect: NSZeroRect operation: NSCompositeSourceAtop fraction: 1.0f];
		}
		pt1.x = editingRangeEndX;
		if (pt1.x >= aRect.origin.x && pt1.x < aRect.origin.x + aRect.size.width) {
            [sEndEditingImage drawAtPoint: pt1 fromRect: NSZeroRect operation: NSCompositeSourceAtop fraction: 1.0f];
		}
	}
	
	/*  Draw end-of-track symbol  */
	if (aRect.origin.x + aRect.size.width > limitx) {
		float defaultLineWidth;
		pt1.x = pt2.x = limitx;
		pt1.y = basey;
		pt2.y = basey + 12.0f;
		[NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
		defaultLineWidth = [NSBezierPath defaultLineWidth];
		[NSBezierPath setDefaultLineWidth: 2.0f];
		pt1.x = pt2.x += 3.0f;
		[NSBezierPath strokeLineFromPoint: pt1 toPoint: pt2];
		[NSBezierPath setDefaultLineWidth: defaultLineWidth];
	}
	
//    if ([self isDragging])
		[self drawSelectRegion];

}

//  Examine whether the mouse pointer is on one of the editing range marks
//  Return value: -1, start pos, 0: none, 1: end pos
//  pt should be in view coordinates
- (int)isMouseOnEditStartPositions:(NSPoint)pt
{
    NSRect visibleRect = [self visibleRect];
	if (pt.y >= visibleRect.origin.y && pt.y <= visibleRect.origin.y + 5) {
		MDTickType startTick, endTick;
		float startx, endx;
		float ppt = [dataSource pixelsPerTick];
		[(MyDocument *)[dataSource document] getEditingRangeStart: &startTick end: &endTick];
		if (startTick >= 0 && startTick < kMDMaxTick && endTick >= startTick) {
			startx = (float)floor(startTick * ppt);
			endx = (float)floor(endTick * ppt);
			if (startx - 5 <= pt.x && pt.x <= startx)
				return -1;
			if (endx <= pt.x && pt.x <= endx + 5)
				return 1;
		}
	}
	return 0;
}

/*  See also: -[MyDocument scaleSelectedTime:]  */
- (void)scaleSelectedTimeWithEvent: (NSEvent *)theEvent undoEnabled:(BOOL)undoEnabled
{
	MDSequence *seq;
	int i, j;
	if (timeScaling == NULL)
		return;  /*  Do nothing  */
	if (theEvent == NULL)
		timeScaling->newEndTick = timeScaling->endTick;  /*  Return to the original  */
	else {
		NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
		float ppt = [dataSource pixelsPerTick];
		timeScaling->newEndTick = mousePt.x / ppt;
		if (timeScaling->newEndTick < timeScaling->startTick)
			timeScaling->newEndTick = timeScaling->startTick;
	}
	seq = [[[dataSource document] myMIDISequence] mySequence];
	for (i = 0; i < timeScaling->ntracks; i++) {
		MDTrack *track = MDSequenceGetTrack(seq, timeScaling->trackNums[i]);
		int n = MDTrackGetNumberOfEvents(track) - timeScaling->startPos[i];  /*  Number of events  */
		MDPointer *pt = MDPointerNew(track);
		MDEvent *ep;
		IntGroupObject *psobj = nil;
		NSMutableData *dt = nil;
		MDTickType *mutableBytes = NULL;
		MDPointerSetPosition(pt, timeScaling->startPos[i]);
		if (undoEnabled && n > 0) {
			psobj = [[IntGroupObject allocWithZone:[self zone]] init];
			IntGroupAdd([psobj pointSet], timeScaling->startPos[i], n);
			dt = [[NSMutableData allocWithZone:[self zone]] initWithLength:sizeof(MDTickType) * n];
			mutableBytes = (MDTickType *)[dt mutableBytes];
		}
		for (ep = MDPointerCurrent(pt), j = 0; ; ep = MDPointerForward(pt), j++) {
			MDTickType tick = timeScaling->originalTicks[i][j];
			if (timeScaling->newEndTick != timeScaling->endTick) {
				if (tick < timeScaling->endTick)
                    tick = timeScaling->startTick + (MDTickType)((double)(tick - timeScaling->startTick) * (timeScaling->newEndTick - timeScaling->startTick) / (timeScaling->endTick - timeScaling->startTick));
				else
					tick += (timeScaling->newEndTick - timeScaling->endTick);
			}
			if (ep == NULL) {
				if (undoEnabled) {
					if (n > 0) {
                        [[dataSource document] modifyTick:dt ofMultipleEventsAt:psobj inTrack:timeScaling->trackNums[i] mode:MyDocumentModifySet destinationPositions:nil setSelection:NO];
						[dt release];
						[psobj release];
					}
					[[dataSource document] changeTrackDuration:tick ofTrack:timeScaling->trackNums[i]];	
				} else {
					MDTrackSetDuration(track, tick);
				}
				break;
			} else {
				if (undoEnabled)
					mutableBytes[j] = tick;
				else
					MDSetTick(ep, tick);
			}
		}
	}
	[dataSource reloadClientViews];
}

- (void)doMouseDown: (NSEvent *)theEvent
{
	NSPoint pt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	int n = [self isMouseOnEditStartPositions:pt];
	if (n != 0) {
		/*  Mofity selectPoints so that the 'other' edit start/end position
		    looks like the dragging start points  */
		MDTickType startTick, endTick;
		float ppt = [dataSource pixelsPerTick];
		[(MyDocument *)[dataSource document] getEditingRangeStart: &startTick end: &endTick];
		if (n < 0)
			pt.x = endTick * ppt;
		else
			pt.x = startTick * ppt;
		[selectPoints replaceObjectAtIndex: 0 withObject: [NSValue valueWithPoint:pt]];
		if (n == 1 && ([theEvent modifierFlags] & (NSAlternateKeyMask | NSShiftKeyMask)) && startTick < endTick) {
			/*  Scale selected time: initialize the internal information  */
			int i, j;
			int32_t trackNo;
			MDTrack *track;
			MDSequence *seq = [[[dataSource document] myMIDISequence] mySequence];
			timeScaling = (TimeScalingRecord *)calloc(sizeof(TimeScalingRecord), 1);
			timeScaling->startTick = startTick;
			timeScaling->endTick = endTick;
			j = MDSequenceGetNumberOfTracks(seq);
			timeScaling->trackNums = (int *)calloc(sizeof(int), j);
			for (i = 0; (trackNo = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
				if (![self isFocusTrack:trackNo])
					continue;
				timeScaling->trackNums[timeScaling->ntracks] = trackNo;
				timeScaling->ntracks++;
			}
			timeScaling->trackNums = (int *)realloc(timeScaling->trackNums, sizeof(int) * timeScaling->ntracks);
			timeScaling->startPos = (int32_t *)calloc(sizeof(int32_t), timeScaling->ntracks);
			timeScaling->originalTicks = (MDTickType **)calloc(sizeof(MDTickType *), timeScaling->ntracks);
			for (i = 0; i < timeScaling->ntracks; i++) {
				MDPointer *pt;
				MDEvent *ep;
				track = MDSequenceGetTrack(seq, timeScaling->trackNums[i]);
				pt = MDPointerNew(track);
				if (MDPointerJumpToTick(pt, startTick)) {
					timeScaling->startPos[i] = MDPointerGetPosition(pt);
				} else {
					timeScaling->startPos[i] = MDTrackGetNumberOfEvents(track);
				}
				timeScaling->originalTicks[i] = (MDTickType *)calloc(sizeof(MDTickType), MDTrackGetNumberOfEvents(track) - timeScaling->startPos[i] + 1);  /*  +1 for end-of-track  */
				for (ep = MDPointerCurrent(pt), j = 0; ep != NULL; ep = MDPointerForward(pt), j++) {
					timeScaling->originalTicks[i][j] = MDGetTick(ep);
				}
				MDPointerRelease(pt);
				timeScaling->originalTicks[i][j] = MDTrackGetDuration(track);
			}
		}
	} else if ((initialModifierFlags & NSCommandKeyMask)) {
		/*  Command + click/drag is similar to shift + click/drag, except that
		 all events in the new editing range are added to the selection  */
		/*  Do nothing; this avoids deselecting the current selection  */
	} else {
		[super doMouseDown: theEvent];
	}
}

- (int)modifyLocalGraphicTool:(int)originalGraphicTool
{
	if (originalGraphicTool == kGraphicRectangleSelectTool || originalGraphicTool == kGraphicPencilTool)
		originalGraphicTool = kGraphicIbeamSelectTool;
	return originalGraphicTool;
}

- (void)doMouseDragged: (NSEvent *)theEvent
{
	if (timeScaling != NULL) {
		[self scaleSelectedTimeWithEvent:theEvent undoEnabled:NO];
        [(MyDocument *)[dataSource document] setEditingRangeStart:timeScaling->startTick end:timeScaling->newEndTick];
		return;
	}
	
	[super doMouseDragged: theEvent];
	if (selectionPath != nil) {
		int i;
		GraphicClientView *view;
		NSRect rect;

		rect = [selectionPath bounds];

		/*  Command + drag: modify selection path with current editing range  */
		if (initialModifierFlags & NSCommandKeyMask) {
			MDTickType tick1, tick2;
			[(MyDocument *)[dataSource document] getEditingRangeStart: &tick1 end: &tick2];
			if (tick1 >= 0 && tick2 < kMDMaxTick && tick1 <= tick2) {
				float ppt = [dataSource pixelsPerTick];
				float x1 = tick1 * ppt;
				float x2 = tick2 * ppt;
				float x3 = rect.origin.x + rect.size.width;
				if (x2 > x3)
					x3 = x2;
				if (x1 < rect.origin.x)
					rect.origin.x = x1;
				rect.size.width = x3 - rect.origin.x;
				[self setSelectRegion: [NSBezierPath bezierPathWithRect: rect]];
			}
		}
		
		/*  Set the selection paths for other clientViews  */
		for (i = 1; (view = [dataSource clientViewAtIndex: i]) != nil; i++) {
			NSRect viewRect = [view bounds];
			rect.origin.y = viewRect.origin.y - 1.0f;
			rect.size.height = viewRect.size.height + 2.0f;
			[view setSelectRegion: [NSBezierPath bezierPathWithRect: rect]];
		}
	}
}

- (void)doMouseUp: (NSEvent *)theEvent
{
	NSPoint pt1, pt2;
	MDTickType tick1, tick2;
    int i;
	int32_t trackNo;
	GraphicClientView *view;
	BOOL shiftDown = (([theEvent modifierFlags] & NSShiftKeyMask) != 0);
	MyDocument *document = (MyDocument *)[dataSource document];
    float ppt = [dataSource pixelsPerTick];

	/*  Clear the selection paths for other clientViews  */
	for (i = 1; (view = [dataSource clientViewAtIndex: i]) != nil; i++) {
		[view setSelectRegion: nil];
	}
	
	if (timeScaling != NULL) {
		/*  Time scaling  */
        /*  If this is the first call since start, ask the user whether
            she wants to insert tempo.  */
        static BOOL sFirstInvocation = YES;
        int insertTempo = 0;
        NSString *str = MyAppCallback_getObjectGlobalSettings(@"scale_selected_time_dialog.insert_tempo");
        NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        if (str == nil) {
            insertTempo = 0;
        } else if (strtol([str UTF8String], NULL, 0) == 0) {
            insertTempo = 0;
        } else insertTempo = 1;
        if (sFirstInvocation) {
            NSAlert *alert = [[NSAlert alloc] init];
            int response;
            [alert setMessageText:[NSString stringWithFormat:@"Tempo events %s inserted to keep timings. OK?", (insertTempo ? "ARE" : "are NOT")]];
            [alert setInformativeText:@"This setting can be changed anytime by 'Scale Selected Time' dialog."];
            [alert addButtonWithTitle:[NSString stringWithFormat:@"OK, %s insert", (insertTempo ? "do" : "don't")]];
            [alert addButtonWithTitle:@"Cancel"];
            [alert addButtonWithTitle:[NSString stringWithFormat:@"NO, %s insert", (insertTempo ? "don't" : "do")]];
            [alert setAlertStyle:NSWarningAlertStyle];
            response = [alert runModal];
            [alert autorelease];
            if (response == NSAlertThirdButtonReturn) {
                insertTempo = !insertTempo;
                MyAppCallback_setObjectGlobalSettings(@"scale_selected_time_dialog.insert_tempo", [NSString stringWithFormat:@"%d", insertTempo]);

            } else if (response == NSAlertSecondButtonReturn) {
                return;
            }
            sFirstInvocation = NO;
        }
		/*  Register undo for selections and editing range  */
	/*	[document getEditingRangeStart: &tick1 end: &tick2]; */
		[[[self undoManager] prepareWithInvocationTarget:document]
         setEditingRangeStart:timeScaling->startTick end:timeScaling->endTick];

        /*  Revert temporary scaling  */
        [self scaleSelectedTimeWithEvent:nil undoEnabled:NO];
        
        /*  Scale time with undo registration  */
        timeScaling->newEndTick = mousePt.x / ppt;
        if (timeScaling->newEndTick < timeScaling->startTick)
            return;
        [document scaleTimeFrom:timeScaling->startTick to:timeScaling->endTick newDuration:timeScaling->newEndTick - timeScaling->startTick insertTempo:insertTempo setSelection:NO];
		tick1 = timeScaling->startTick;
		tick2 = timeScaling->newEndTick;
		for (i = 0; i < timeScaling->ntracks; i++)
			free(timeScaling->originalTicks[i]);
		free(timeScaling->originalTicks);
		free(timeScaling->startPos);
		free(timeScaling->trackNums);
		free(timeScaling);
		timeScaling = NULL;
        return;
		
	} else {
		
		if (isLoupeDragging) {
			[super doMouseUp: theEvent];
			return;
		}

		/*  Editing range  */
		pt1 = [[selectPoints objectAtIndex: 0] pointValue];
		if (isDragging) {
			pt2 = [[selectPoints objectAtIndex: 1] pointValue];
		} else pt2 = pt1;
		tick1 = (MDTickType)floor(pt1.x / ppt);
		tick2 = (MDTickType)floor(pt2.x / ppt);
		if (tick1 < 0)
			tick1 = 0;
		if (tick2 < 0)
			tick2 = 0;
		if (tick1 > tick2) {
			MDTickType tick3 = tick1;
			tick1 = tick2;
			tick2 = tick3;
		}
		if (initialModifierFlags & NSCommandKeyMask) {
			MDTickType rtick1, rtick2;
			[document getEditingRangeStart: &rtick1 end: &rtick2];
			if (rtick1 >= 0 && rtick2 < kMDMaxTick && rtick1 <= rtick2) {
				if (rtick1 < tick1)
					tick1 = rtick1;
				if (rtick2 > tick2)
					tick2 = rtick2;
			}
		}
	}
	
	if (tick1 < tick2) {
		/*  Select all events within this tick range  */
		for (i = 0; (trackNo = [self sortedTrackNumberAtIndex: i]) >= 0; i++) {
			MDTrack *track;
			MDPointer *pt;
			IntGroup *pset;
			MDSelectionObject *obj;
			int32_t pos1, pos2;
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
			MDPointerJumpToTick(pt, tick1);
			pos1 = MDPointerGetPosition(pt);
			MDPointerJumpToTick(pt, tick2);
			pos2 = MDPointerGetPosition(pt);
			if (pos1 < pos2) {
				if (IntGroupAdd(pset, pos1, pos2 - pos1) != kMDNoError)
					break;
				obj = [[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: pset];
				if (shiftDown) {
					[document toggleSelection: obj inTrack: trackNo sender: self];
				} else {
					[document setSelection: obj inTrack: trackNo sender: self];
				}
				[obj release];
			}
			IntGroupRelease(pset);
			MDPointerRelease(pt);
		}
	}
	
	/*  Change editing range  */
	if (shiftDown) {
		MDTickType oldTick1, oldTick2;
		[document getEditingRangeStart: &oldTick1 end: &oldTick2];
		if (oldTick1 >= 0 && oldTick1 < tick1)
			tick1 = oldTick1;
		if (oldTick2 > tick2)
			tick2 = oldTick2;
	}
	[document setEditingRangeStart: tick1 end: tick2];
	if (tick1 == tick2 && [theEvent clickCount] >= 2)
		[[dataSource playingViewController] setCurrentTick: tick1];
}

- (void)doMouseMoved: (NSEvent *)theEvent
{
	NSPoint pt;
	int n;
	unsigned modifierFlags;
	localGraphicTool = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
	if ([theEvent type] == NSFlagsChanged) {
		pt = [self convertPoint:[[self window] convertScreenToBase:[NSEvent mouseLocation]] fromView:nil];
	} else {		
		pt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	}
	modifierFlags = [theEvent modifierFlags];
	n = [self isMouseOnEditStartPositions:pt];
	if (n != 0) {
		if (n == 1 && (modifierFlags & (NSAlternateKeyMask | NSShiftKeyMask))) {
			[[NSCursor horizontalMoveZoomCursor] set];
		} else {
			[[NSCursor horizontalMoveCursor] set];
		}
	} else {
		if ([theEvent modifierFlags] & NSAlternateKeyMask)
			[[NSCursor loupeCursor] set];
		else [[NSCursor IBeamCursor] set];
	}
}

- (void)doFlagsChanged:(NSEvent *)theEvent
{
	[self doMouseMoved:theEvent];
}

@end
