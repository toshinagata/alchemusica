//
//  TimeChartView.m
//  Created by Toshi Nagata on Sat Jan 25 2003.
//
/*
    Copyright (c) 2003-2025 Toshi Nagata. All rights reserved.

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

#include "MDRubyExtern.h"

typedef struct TimeScalingRecord {
	MDTickType startTick;  /*  Start tick of the time region to be scaled   */
	MDTickType endTick;    /*  End tick of the time region to be scaled  */
    /*  The following fields are valid only in non-realtime mode  */
	MDTickType newEndTick; /*  End tick after scaling the time region  */
    BOOL insertTempo;      /*  Do we insert tempo?  */
    BOOL modifyAllTracks;  /*  Modify all tracks (including non-editing ones) */
    /*  The following fields are valid only in realtime mode  */
    MDTimeType startTime;  /*  Time for startTick  */
    MDTimeType endTime;    /*  Time for endTick  */
    MDTimeType newEndTime; /*  End time after scaling tempo  */
    int mode;              /*  0: uniform scaling, 1: linear cresc/decresc. (not implemented yet)  */
    MDTickType tempoEventInterval;  /*  Intervals of newly inserted Tempo events */
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
    MDTickType beginTick, endTick;
	float originx;
	float limitx;
    float basey, maxLabelWidth;
    NSPoint pt1, pt2, pt3;
    NSRect visibleRect = [self visibleRect];
    float editingRangeStartX, editingRangeEndX;

    basey = visibleRect.origin.y + 0.5f;
    limitx = [dataSource tickToPixel:[dataSource sequenceDuration]];

	[self paintEditingRange: aRect startX: &editingRangeStartX endX: &editingRangeEndX];
	
    /*  Draw horizontal axis  */
    [NSBezierPath strokeLineFromPoint: NSMakePoint(aRect.origin.x, basey) toPoint: NSMakePoint(aRect.origin.x + aRect.size.width, basey)];
    
    /*  Draw ticks, labels, and time signatures  */
    maxLabelWidth = [@"0000:00:0000" sizeWithAttributes: nil].width;
    originx = aRect.origin.x - maxLabelWidth;
    if (originx < 0.0f)
        originx = 0.0f;
    beginTick = [dataSource pixelToTick:originx];
    endTick = [dataSource pixelToTick:(aRect.origin.x + aRect.size.width)];
	while (beginTick < endTick) {
		int mediumCount, majorCount, i, numLines;
        int sigNumerator, sigDenominator;
		MDEvent *sig1, *sig2;
		MDTickType sigTick, nextSigTick;
		float interval, startx;
        float widthPerBeat, widthPerMeasure;
		[dataSource verticalLinesFromTick: beginTick timeSignature: &sig1 nextTimeSignature: &sig2 lineInterval: &interval mediumCount: &mediumCount majorCount: &majorCount];
		sigTick = (sig1 == NULL ? 0 : MDGetTick(sig1));
		nextSigTick = (sig2 == NULL ? kMDMaxTick : MDGetTick(sig2));
		if (nextSigTick > endTick)
			nextSigTick = endTick;
        startx = [dataSource tickToPixel:sigTick];
        sigDenominator = (sig1 == NULL ? 4 : (1 << (int)(MDGetMetaDataPtr(sig1)[1])));
        sigNumerator = (sig1 == NULL ? 4 : MDGetMetaDataPtr(sig1)[0]);
        if (sigNumerator == 0)
            sigNumerator = 4;
        [[NSString stringWithFormat: @"%d/%d", sigNumerator, sigDenominator] drawAtPoint: NSMakePoint(startx, basey + 22.0f) withAttributes: nil clippingRect: aRect];
        numLines = (int)floor((nextSigTick - sigTick) / interval) + 1;
		i = (startx >= originx ? 0 : (int)floor((beginTick - sigTick) / interval));
		[[NSColor blackColor] set];
		for ( ; i < numLines; i++) {
            pt1 = NSMakePoint((CGFloat)(floor([dataSource tickToPixel:(sigTick + i * interval)]) + 0.5), basey);
            pt2.x = pt1.x;
			if (pt1.x > limitx)
				[[NSColor grayColor] set];
            if (i % majorCount == 0) {
                /*  Draw label  */
                NSString *label;
                int32_t n1, n2, n3;
                [dataSource convertTick: (MDTickType)floor((sigTick + i * interval) + 0.5) toMeasure: &n1 beat: &n2 andTick: &n3];
                widthPerBeat = [(MyDocument *)[dataSource document] timebase] * 4 / sigDenominator;
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
            [sStartEditingImage drawAtPoint: pt1 fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1.0f];
		}
		pt1.x = editingRangeEndX;
		if (pt1.x >= aRect.origin.x && pt1.x < aRect.origin.x + aRect.size.width) {
            [sEndEditingImage drawAtPoint: pt1 fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1.0f];
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
	
    /*  Draw playing position symbol (even while not playing)  */
    id playingViewController = [[self dataSource] playingViewController];
    float playTick = (float)[playingViewController getCurrentTick];
    pt1.x = [self timeIndicatorLocationFromPos:playTick];
    if (pt1.x >= aRect.origin.x && pt1.x < aRect.origin.x + aRect.size.width) {
        [[NSColor blackColor] set];
        pt1.y = aRect.origin.y;
        pt2.x = pt1.x;
        pt2.y = pt1.y + 6.0;
        [NSBezierPath strokeLineFromPoint:pt1 toPoint:pt2];
        pt1 = pt2;
        pt2.x -= 3.0;
        pt2.y += 6.0;
        pt3 = pt2;
        pt3.x += 6.0;
        [NSBezierPath strokeLineFromPoint:pt1 toPoint:pt2];
        [NSBezierPath strokeLineFromPoint:pt2 toPoint:pt3];
        [NSBezierPath strokeLineFromPoint:pt3 toPoint:pt1];
    }

    [self drawSelectRegion];

}

- (CGFloat)timeIndicatorWidth
{
    return 8.0;
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
		[(MyDocument *)[dataSource document] getEditingRangeStart: &startTick end: &endTick];
		if (startTick >= 0 && startTick < kMDMaxTick && endTick >= startTick) {
            startx = (CGFloat)[dataSource tickToPixel:startTick];
            endx = (CGFloat)[dataSource tickToPixel:endTick];
			if (startx - 5 <= pt.x && pt.x <= startx)
				return -1;
			if (endx <= pt.x && pt.x <= endx + 5)
				return 1;
		}
	}
	return 0;
}

- (void)doMouseDown: (NSEvent *)theEvent
{
	NSPoint pt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
	int n = [self isMouseOnEditStartPositions:pt];
	if (n != 0) {
		/*  Mofity selectPoints so that the 'other' edit start/end position
		    looks like the dragging start points  */
		MDTickType startTick, endTick;
		[(MyDocument *)[dataSource document] getEditingRangeStart: &startTick end: &endTick];
		if (n < 0)
            pt.x = [dataSource tickToPixel:endTick];
		else
            pt.x = [dataSource tickToPixel:startTick];
		[selectPoints replaceObjectAtIndex: 0 withObject: [NSValue valueWithPoint:pt]];
		if (n == 1 && ([theEvent modifierFlags] & (NSAlternateKeyMask | NSShiftKeyMask)) && startTick < endTick) {
            NSString *str;
			/*  Scale selected time: initialize the internal information  */
            timeScaling = calloc(sizeof(TimeScalingRecord), 1);
            timeScaling->startTick = startTick;
            timeScaling->endTick = endTick;
            timeScaling->newEndTick = endTick;
            if ([dataSource isRealTime]) {
                timeScaling->startTime = [dataSource tickToTime:startTick];
                timeScaling->endTime = [dataSource tickToTime:endTick];
                timeScaling->newEndTime = timeScaling->endTime;
                str = MyAppCallback_getObjectGlobalSettings(@"scale_tempo_dialog.tempo_change_style");
                timeScaling->mode = (int)(str == nil ? 0 : strtol([str UTF8String], NULL, 0));
                str = MyAppCallback_getObjectGlobalSettings(@"scale_tempo_dialog.tempo_event_interval");
                timeScaling->tempoEventInterval = (MDTickType)(str == nil ? 0 : strtol([str UTF8String], NULL, 0));
            } else {
                str = MyAppCallback_getObjectGlobalSettings(@"scale_selected_time_dialog.insert_tempo");
                timeScaling->insertTempo = (str != nil && strtol([str UTF8String], NULL, 0) != 0);
                str = MyAppCallback_getObjectGlobalSettings(@"scale_selected_time_dialog.modify_all_tracks");
                timeScaling->modifyAllTracks = (str != nil && strtol([str UTF8String], NULL, 0) != 0);
            }
		}
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
        MyDocument *doc = (MyDocument *)[dataSource document];
        NSPoint mousePt = [self convertPoint:[theEvent locationInWindow] fromView:nil];
        BOOL isRealTime = [dataSource isRealTime];
        if (isRealTime) {
            double dt1, dt2;
            if (timeScaling->endTime != timeScaling->newEndTime)
                //  Restore the original state
                [[doc undoManager] undo];
            timeScaling->newEndTime = [dataSource pixelToTime:mousePt.x];
            if (timeScaling->newEndTime < timeScaling->startTime)
                timeScaling->newEndTime = timeScaling->startTime;
            dt1 = timeScaling->endTime - timeScaling->startTime;
            dt2 = timeScaling->newEndTime - timeScaling->startTime;
            if (dt2 < dt1 * 0.01)
                timeScaling->newEndTime = timeScaling->startTime + ceil(dt1 * 0.01);
            if (timeScaling->endTime != timeScaling->newEndTime) {
                [doc scaleTempoFrom:timeScaling->startTick to:timeScaling->endTick by: dt1/dt2 scalingMode:timeScaling->mode tempoEventInterval:timeScaling->tempoEventInterval];
            }
        } else {
            if (timeScaling->endTick != timeScaling->newEndTick)
                //  Restore the original state
                [[doc undoManager] undo];
            timeScaling->newEndTick = [dataSource pixelToTick:mousePt.x];
            if (timeScaling->newEndTick < timeScaling->startTick)
                timeScaling->newEndTick = timeScaling->startTick;
            if (timeScaling->endTick != timeScaling->newEndTick) {
                [doc scaleTicksFrom:timeScaling->startTick to:timeScaling->endTick newDuration:(timeScaling->newEndTick - timeScaling->startTick) insertTempo:timeScaling->insertTempo modifyAllTracks:timeScaling->modifyAllTracks setSelection:NO];
            }
        }
		return;
	}
	
	[super doMouseDragged: theEvent];
	if (selectionPath != nil) {
		int i;
		GraphicClientView *view;
		NSRect rect;

		rect = [selectionPath bounds];

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

	/*  Clear the selection paths for other clientViews  */
	for (i = 1; (view = [dataSource clientViewAtIndex: i]) != nil; i++) {
		[view setSelectRegion: nil];
	}
	
	if (timeScaling != NULL) {

        /*  Time scaling  */
        NSString *str;
        BOOL showDialog, undoNeeded;
        BOOL isRealTime = [dataSource isRealTime];
        if (isRealTime) {
            double multiple = (double)(timeScaling->endTime - timeScaling->startTime) / (timeScaling->newEndTime - timeScaling->startTime);
            /*  Show tempo scaling dialog (unless the user doesn't want it)  */
            str = MyAppCallback_getObjectGlobalSettings(@"scale_tempo_dialog.show_dialog_on_dragging");
            showDialog = (str != nil && strtol([str UTF8String], NULL, 0) != 0);
            undoNeeded = (timeScaling->endTime != timeScaling->newEndTime);
            if (showDialog) {
                double *dp;
                int n, status;
                status = Ruby_callMethodOfDocument("scale_tempo_dialog", document, 0, "qqd;D", (int64_t)timeScaling->startTick, (int64_t)timeScaling->endTick, multiple, &n, &dp);
                if (status != 0) {
                    Ruby_showError(status);
                    return;
                }
                if (n == 0) {
                    //  Dialog is canceled; we undo the last operation
                    multiple = 1.0;  //  Disable operation
                } else {
                    //  timeScaling fields are updated according to the dialog results and call scaleTempoFrom: again
                    timeScaling->startTick = (MDTickType)dp[0];
                    timeScaling->endTick = (MDTickType)dp[1];
                    multiple = (double)dp[2];
                    timeScaling->mode = (int)dp[3];
                    timeScaling->tempoEventInterval = (MDTickType)dp[4];
                }
            }
            if (undoNeeded)
                [[document undoManager] undo];
            if (multiple != 1.0)
                [document scaleTempoFrom:timeScaling->startTick to:timeScaling->endTick by:multiple scalingMode:timeScaling->mode tempoEventInterval:timeScaling->tempoEventInterval];
        } else {
            /*  Show tick scaling dialog (unless the user doesn't want it)  */
            str = MyAppCallback_getObjectGlobalSettings(@"scale_selected_time_dialog.show_dialog_on_dragging");
            showDialog = (str != nil && strtol([str UTF8String], NULL, 0) != 0);
            undoNeeded = (timeScaling->endTick != timeScaling->newEndTick);
            if (showDialog) {
                double *dp;
                int n, status;
                status = Ruby_callMethodOfDocument("scale_selected_time_dialog", document, 0, "qqq;D", (int64_t)timeScaling->startTick, (int64_t)timeScaling->endTick, (int64_t)(timeScaling->newEndTick - timeScaling->startTick), &n, &dp);
                if (status != 0) {
                    Ruby_showError(status);
                    return;
                }
                if (n == 0) {
                    //  Dialog is canceled; we undo the last operation
                    timeScaling->endTick = timeScaling->newEndTick;  //  Disable operation
                } else {
                    //  timeScaling fields are updated according to the dialog results and call scaleTicksFrom: again
                    timeScaling->startTick = (MDTickType)dp[0];
                    timeScaling->endTick = (MDTickType)dp[1];
                    timeScaling->newEndTick = (MDTickType)(dp[0] + dp[2]);
                    timeScaling->insertTempo = (BOOL)dp[3];
                    timeScaling->modifyAllTracks = (BOOL)dp[4];
                }
            }
            if (undoNeeded)
                [[document undoManager] undo];
            if (timeScaling->endTick != timeScaling->newEndTick)
                [document scaleTicksFrom:timeScaling->startTick to:timeScaling->endTick newDuration:(timeScaling->newEndTick - timeScaling->startTick) insertTempo:timeScaling->insertTempo modifyAllTracks:timeScaling->modifyAllTracks setSelection:YES];
        }
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
        tick1 = (MDTickType)[dataSource pixelToTick:pt1.x];
        tick2 = (MDTickType)[dataSource pixelToTick:pt2.x];
		if (tick1 < 0)
			tick1 = 0;
		if (tick2 < 0)
			tick2 = 0;
		if (tick1 > tick2) {
			MDTickType tick3 = tick1;
			tick1 = tick2;
			tick2 = tick3;
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
            }
            obj = [[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: pset];
            obj->track = track;
            if (shiftDown) {
                [document toggleSelection: obj inTrack: trackNo sender: self];
            } else {
                [document setSelection: obj inTrack: trackNo sender: self];
            }
            [obj release];
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
	NSUInteger modifierFlags;
	localGraphicTool = [self modifyLocalGraphicTool:[[self dataSource] graphicTool]];
	if ([theEvent type] == NSFlagsChanged) {
        pt = [self convertPoint:[[self window] mouseLocationOutsideOfEventStream] fromView:nil];
//		pt = [self convertPoint:[[self window] convertPointFromScreen:[NSEvent mouseLocation]] fromView:nil];
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
