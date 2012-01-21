/*
   GraphicWindowController.m
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

#import "GraphicWindowController.h"
#import "NSWindowControllerAdditions.h"
#import "GraphicSplitterView.h"
#import "PianoRollView.h"
#import "PianoRollRulerView.h"
#import "StripChartView.h"
#import "StripChartRulerView.h"
#import "TimeChartView.h"
#import "MyDocument.h"
#import "MyMIDISequence.h"
#import "ColorCell.h"
#import "TrackAttributeCell.h"
#import "MyPopUpButtonCell.h"
#import "MyComboBoxCell.h"
#import "MDObjects.h"
#import "MyWindow.h"
#import "PlayingViewController.h"
#import "RemapDevicePanelController.h"
#import "RecordPanelController.h"
#import "MyAppController.h"

const float kMinimumTickIntervalsInPixels = 8.0;

enum {
	kPlusButtonTag = 1000,
	kMinusButtonTag = 1001,
	kShrinkButtonTag = 2000,
	kExpandButtonTag = 2001,
	kSelectButtonTag = 3000,
	kIbeamButtonTag = 3001,
	kPencilButtonTag = 3002,
	kShapePopUpTag = 3003,
	kModePopUpTag = 3004,
	kInfoTextTag = 3005,
	kEditingRangeStartTextTag = 3006,
	kEditingRangeEndTextTag = 3007,
	kQuantizePopUpTag = 3008,
	kLinearMenuTag = 3010,
	kParabolaMenuTag = 3011,
	kArcMenuTag = 3012,
	kSigmoidMenuTag = 3013,
	kRandomMenuTag = 3014,
	kSetMenuTag = 3050,
	kAddMenuTag = 3051,
	kScaleMenuTag = 3052,
	kLimitMaxMenuTag = 3053,
	kLimitMinMenuTag = 3054,
	kQuantizeMenuTag = 3100
};

/*  IDs for track list tableView  */
static NSString *sTableColumnIDs[] = {
	@"number", @"edit", @"visible", @"name", @"ch", @"solo", @"mute", @"device"
};

enum {
	kTrackNumberID = 0,
	kEditableID = 1,
	kVisibleID = 2,
	kTrackNameID = 3,
	kChannelID = 4,
	kSoloID = 5,
	kMuteID = 6,
	kDeviceNameID = 7
};

static NSImage *sPencilSmallImage = NULL;
static NSImage *sEyeOpenImage = NULL;
static NSImage *sEyeCloseImage = NULL;
static NSImage *sSpeakerImage = NULL;
static NSImage *sSpeakerGrayImage = NULL;
static NSImage *sMuteImage = NULL;
static NSImage *sMuteNonImage = NULL;
static NSImage *sSoloImage = NULL;
static NSImage *sSoloNonImage = NULL;

static NSString *sNeedsReloadClientViewNotification = @"reload client views";

static int
sTableColumnIDToInt(id identifier)
{
	int i;
	for (i = sizeof(sTableColumnIDs) / sizeof(sTableColumnIDs[0]) - 1; i >= 0; i--)
		if ([sTableColumnIDs[i] isEqualToString: identifier])
			return i;
	return -1;
}

@implementation GraphicWindowController

- (float)rulerWidth
{
	return 40.0;
}

- (id)init {
    self = [super initWithWindowNibName:@"GraphicWindow"];
    [self setShouldCloseDocument: YES];
//	myTrack = NULL;
//	trackInfo = [[NSMutableArray allocWithZone: [self zone]] init];
//	editFlags = nil;
	lastMouseClientViewIndex = -1;
    return self;
}

- (void)dealloc {
	int i;
    if (trackingRectTag != 0)
        [myMainView removeTrackingRect: trackingRectTag];
    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
    if (calib != NULL)
        MDCalibratorRelease(calib);
	for (i = 0; i < myClientViewsCount; i++) {
		[records[i].client release];
		[records[i].ruler release];
		[records[i].splitter release];
	//	if (records[i].calib != NULL)
	//		MDCalibratorRelease(records[i].calib);
	}
//	[editFlags release];
//	[trackInfo release];
	if (sortedTrackNumbers != NULL)
		free(sortedTrackNumbers);
	if (zoomUndoBuffer != nil)
		[zoomUndoBuffer release];
    [super dealloc];
}

- (void)windowWillClose:(NSNotification *)notification
{
	[playingViewController pressStopButton:self];
}

#pragma mark ==== NSWindowControllerAdditions overrides ====

+ (BOOL)canContainMultipleTracks
{
    return YES;
}

#pragma mark ==== Handling track lists ====

/*
- (TrackInfo)trackInfoAtIndex: (int)index
{
	TrackInfo info;
	if (index < 0 || index >= [trackInfo count]) {
		info.trackNum = -1;
	} else {
		[[trackInfo objectAtIndex: index] getValue: &info];
	}
	return info;
}

- (void)setTrackInfo: (TrackInfo)info atIndex: (int)index
{
	NSValue *value = [NSValue valueWithBytes: &info objCType:@encode(TrackInfo)];
	if (index >= 0 && index < [trackInfo count]) {
		[trackInfo replaceObjectAtIndex: index withObject: value];
	} else if (index == [trackInfo count]) {
		[trackInfo addObject: value];
	}
}

- (int)lookupTrack: (int)track
{
	int i;
	TrackInfo info;
	for (i = [trackInfo count] - 1; i >= 0; i--) {
		info = [self trackInfoAtIndex: i];
		if (info.trackNum == track)
			return i;
	}
	return -1;
}

- (BOOL)containsTrack: (int)track
{
	return ([self lookupTrack: track] >= 0);
}

- (void)addTrack: (int)track
{
    int i;
	TrackInfo info;
	if (![self containsTrack: track]) {
		info.trackNum = track;
		//  If this is the first track, then it gets focus
		info.focusFlag = ([trackInfo count] == 0 ? 1 : 0);
		[self setTrackInfo: info atIndex: [trackInfo count]];
        for (i = 0; i < myClientViewsCount; i++)
            [records[i].client addTrack: track];
		[sortedTrackNumbers release];
		sortedTrackNumbers = nil;
    }
}
*/

- (void)setFocusFlag: (BOOL)flag onTrack: (int)trackNum extending: (BOOL)extendFlag
{
	int i;
	MDTrackAttribute attr;
	MyMIDISequence *seq = [[self document] myMIDISequence];
	if (!extendFlag) {
		for (i = [self trackCount] - 1; i >= 0; i--) {
			attr = [seq trackAttributeAtIndex: i];
			if (i == trackNum && flag)
				attr |= kMDTrackAttributeEditable;
			else
				attr &= ~kMDTrackAttributeEditable;
			[seq setTrackAttribute: attr atIndex: i];
		}
	} else {
		attr = [seq trackAttributeAtIndex: trackNum];
		if (flag)
			attr |= kMDTrackAttributeEditable;
		else
			attr &= ~kMDTrackAttributeEditable;
		[seq setTrackAttribute: attr atIndex: trackNum];
	}
	visibleTrackCount = -1;  /*  Needs update  */
	[self reloadClientViews];
}

- (BOOL)isFocusTrack: (int)trackNum
{
	if (trackNum >= 0 && trackNum < [self trackCount]) {
		MDTrackAttribute attr = [[[self document] myMIDISequence] trackAttributeAtIndex: trackNum];
		return ((attr & kMDTrackAttributeEditable) != 0);
	} else return NO;
//	return [myTableView isRowSelected: trackNum];
/*	int n;
	n = [self lookupTrack: trackNum];
	if (n >= 0)
		return ([self trackInfoAtIndex: n].focusFlag != 0);
	else return NO; */
}

- (BOOL)isTrackSelected: (long)trackNo
{
	return [myTableView isRowSelected: trackNo];
}

- (void)setIsTrackSelected: (long)trackNo flag: (BOOL)flag
{
	if (flag)
		[myTableView selectRowIndexes: [NSIndexSet indexSetWithIndex: trackNo] byExtendingSelection: YES];
	else
		[myTableView deselectRow: trackNo];
}

- (long)trackCount
{
	return [[[self document] myMIDISequence] trackCount];
}


/*
- (int)trackNumberAtIndex: (int)index
{
	TrackInfo info;
    if (index >= 0 && index < [trackInfo count]) {
		info = [self trackInfoAtIndex: index];
		return info.trackNum;
	} else return -1;
}
*/

- (int)sortedTrackNumberAtIndex: (int)index
{
	int n = [self trackCount];
	if (sortedTrackNumbers == NULL || visibleTrackCount < 0) {
		int i, j, k;
	//	TrackInfo info;
		if (sortedTrackNumbers == NULL)
			sortedTrackNumbers = (int *)malloc(sizeof(int) * n);
		else
			sortedTrackNumbers = (int *)realloc(sortedTrackNumbers, sizeof(int) * n);
		j = k = 0;
		for (i = 0; i < n; i++) {
			MDTrackAttribute attr = [[[self document] myMIDISequence] trackAttributeAtIndex: i];
			if (!(attr & kMDTrackAttributeHidden)) {
				if (attr & kMDTrackAttributeEditable) {
					memmove(sortedTrackNumbers + j + 1, sortedTrackNumbers + j, sizeof(int) * (k - j));
					sortedTrackNumbers[j++] = i;
				} else {
					sortedTrackNumbers[k] = i;
				}
				k++;
			}
		}
		visibleTrackCount = k;
	}
	if (index >= 0 && index < visibleTrackCount)
		return sortedTrackNumbers[index];
	else return -1;
}

- (long)visibleTrackCount
{
	if (sortedTrackNumbers == NULL || visibleTrackCount < 0)
		[self sortedTrackNumberAtIndex: 0];  /*  Rebuild the internal cache; the returned value is discarded  */
	return visibleTrackCount;
}

/*
- (void)addTracksInArray: (NSArray *)array
{
	id object;
	NSEnumerator *enumerator = [array objectEnumerator];
	while ((object = [enumerator nextObject]) != nil) {
		[self addTrack: [object intValue]];
	}
}

- (void)removeTrack: (int)track
{
    int i, index;
	index = [self lookupTrack: track];
	if (index >= 0) {
		TrackInfo info = [self trackInfoAtIndex: index];
		[trackInfo removeObjectAtIndex: index];
        for (i = 0; i < myClientViewsCount; i++)
            [records[i].client removeTrack: track];
		[sortedTrackNumbers release];
		sortedTrackNumbers = nil;
		if (info.focusFlag) {
			//  One of the tracks acquires focus in place of the removed track
		//	if (index < [trackInfo count]) {
		//		[self setFocusOnTrack: index];
		//	} else if ([trackInfo count] > 0) {
		//		[self setFocusOnTrack: index - 1];
		//	}
		}
    }
}

- (void)removeTrackAndFill: (int)track
{
	int i;
	TrackInfo info;
	for (i = [trackInfo count] - 1; i >= 0; i--) {
		info = [self trackInfoAtIndex: i];
		if (info.trackNum > track) {
			info.trackNum--;
			[self setTrackInfo: info atIndex: i];
		}
	}
	[self removeTrack: track];
	//  The following two lines become redundant when removeTrack succeeded,
	//  but they are still here in case no track is to be removed but some
	//  tracks get their track numbers changed.
	[sortedTrackNumbers release];
	sortedTrackNumbers = nil;
}

- (void)removeTracksInArray: (NSArray *)array
{
	id object;
	NSEnumerator *enumerator = [array objectEnumerator];
	while ((object = [enumerator nextObject]) != nil) {
		[self removeTrack: [object intValue]];
	}
}

- (NSMenu *)trackMenu
{
	NSMenu *menu;
	int i, n;
	NSMenuItem *item;
	NSString *title;
	menu = [[[NSMenu allocWithZone: [self zone]] init] autorelease];
	[menu setAutoenablesItems: NO];
	n = [[[self document] myMIDISequence] trackCount];
	for (i = 0; i < n; i++) {
		title = [NSString stringWithFormat: @"%d:%@", i, [[[self document] myMIDISequence] trackName: i]];
		item = (NSMenuItem *)[menu addItemWithTitle: title action: @selector(trackMenuItemSelected:) keyEquivalent: @""];
		[item setTag: i];
		[item setTarget: self];
		if ([self containsTrack: i]) {
//			NSLog(@"[item setEnabled: NO]");
			[item setEnabled: NO];
		}
	}
	return menu;
}
*/
/*
- (void)setEditFlags: (NSData *)data
{
	int i, n, length;
	NSMutableData *newEditFlags;
	n = [[[self document] myMIDISequence] trackCount];
	if (n == 0)
		return;
//	[editFlags release];
	newEditFlags = [[NSMutableData allocWithZone: [self zone]] initWithLength: n];
	length = [data length];
	for (i = 0; i < n; i++) {
		((unsigned char *)[newEditFlags mutableBytes])[i] =
			(i < length ? ((const unsigned char *)[data bytes])[i] : 0);
	}
//	editFlags = newEditFlags;
	for (i = 0; i < myClientViewsCount; i++)
		[records[i].client reloadData];
}
*/
/*
- (NSData *)editFlags
{
	return editFlags;
}
*/

#pragma mark ==== Pixel/tick conversion ====

- (float)pixelsPerQuarter
{
	return pixelsPerQuarter;
}

- (void)setPixelsPerQuarter: (float)newPixelsPerQuarter;
{
 //   NSRect visibleRect;
    float pos;
	if (pixelsPerQuarter == newPixelsPerQuarter)
        return;
    if (myClientViewsCount > 0) {
        /*  Keep scroll position at the left side  */
		pos = [self scrollPositionOfClientViews];
        pos *= newPixelsPerQuarter / pixelsPerQuarter;
    }
    pixelsPerQuarter = newPixelsPerQuarter;
	[self reloadClientViews];
	[self scrollClientViewsToPosition: pos];
}

- (float)pixelsPerTick
{
    return pixelsPerQuarter / [[self document] timebase];
}

- (MDTickType)quantizedTickFromPixel: (float)pixel
{
	float ppt = [self pixelsPerTick];
	float timebase = [[self document] timebase];
	float tickQuantum = quantize * timebase;
	MDTickType tick = pixel / ppt;
	MDTickType basetick;  /*  The tick at the beginning of the bar  */
	MDTickType qtick;
	long measure, beat, mtick;
	if (tickQuantum == 0.0)
		return tick;
	MDCalibratorTickToMeasure(calib, tick, &measure, &beat, &mtick);
	basetick = MDCalibratorMeasureToTick(calib, measure, 1, 0);
	qtick = basetick + floor((float)(tick - basetick) / tickQuantum + 0.5) * tickQuantum;
	return qtick;
}

- (float)quantizedPixelFromPixel: (float)pixel
{
	if (quantize == 0.0)
		return pixel;
	else return [self quantizedTickFromPixel: pixel] * [self pixelsPerTick];
}

- (float)pixelQuantum
{
	if (quantize == 0.0)
		return 1.0;
	else return quantize * [self pixelsPerQuarter];
}

#pragma mark ==== Time Indicator ====

- (NSBezierPath *)timeIndicatorPathAtBeat: (float)beat
{
//	float beat;
	NSRect aRect;
	NSPoint pt;
	NSBezierPath *path;
	int n;
//	if (![[[self document] myMIDISequence] isPlaying])
//		return nil;
//	beat = [[[self document] myMIDISequence] playingBeat];
//	if (beat < 0)
//		return nil;
	aRect = [[records[0].client superview] bounds];
	pt.x = beat * [self pixelsPerQuarter];
	if (pt.x < aRect.origin.x || pt.x > aRect.origin.x + aRect.size.width)
		return nil;
	pt.y = 0;
	pt = [myFloatingView convertPoint: pt fromView: records[0].client];
	path = [NSBezierPath bezierPath];
	for (n = 0; n < myClientViewsCount; n++) {
		aRect = [myFloatingView convertRect: [[records[n].client superview] bounds] fromView: records[n].client];
		pt.y = aRect.origin.y + aRect.size.height;
		[path moveToPoint: pt];
		pt.y = aRect.origin.y;
		[path lineToPoint: pt];
	}
	return path;
}

- (NSBezierPath *)bouncingBallPathAtBeat: (float)beat
{
	return nil;
}

- (void)showTimeIndicatorAtBeat: (float)beat
{
	NSBezierPath *path, *bpath;
//	float beat;
	NSWindow *theWindow = [self window];
	
//	beat = [[[self document] myMIDISequence] playingBeat];
	timeIndicatorPos = beat;
	if (beat < 0)
		return;
	path = [self timeIndicatorPathAtBeat: beat];
	if (path) {
		NSRect bounds;
		bounds = [path bounds];
		bpath = [self bouncingBallPathAtBeat: beat];
		if (bpath)
			bounds = NSUnionRect(bounds, [bpath bounds]);
		bounds = NSInsetRect(bounds, -1, -1);
		bounds = [myFloatingView convertRect: bounds toView: nil];	//  window base coordinate
	//	NSLog(@"bounds = %@", NSStringFromRect(bounds));
		timeIndicatorRect = bounds;
		[theWindow restoreCachedImage];
		[theWindow discardCachedImage];
		[theWindow cacheImageInRect: bounds];
		[myFloatingView lockFocus];
		[path stroke];
		if (bpath)
			[bpath fill];
		[myFloatingView unlockFocus];
		[theWindow flushWindowIfNeeded];
	}
}

- (void)hideTimeIndicator
{
	NSWindow *theWindow = [self window];
	[theWindow restoreCachedImage];
	[theWindow discardCachedImage];
	[theWindow flushWindowIfNeeded];
	timeIndicatorPos = -1.0;
	timeIndicatorRect = NSMakeRect(0, 0, 0, 0);
}

- (void)invalidateTimeIndicatorCachedImage
{
	NSRect bounds;
	NSBezierPath *path;
	int n;
	NSView *view;
	if (timeIndicatorPos >= 0) {
		/*  Redraw the 'timeIndicatorRect' portion of each splitter view  */
		for (n = 0; n < myClientViewsCount; n++) {
			view = records[n].splitter;
			[view setNeedsDisplayInRect: [view convertRect: timeIndicatorRect fromView: nil]];
		}
		/*  Calculate the 'current' position of the time indicator  */
		path = [self timeIndicatorPathAtBeat: timeIndicatorPos];
		if (path != nil)
			bounds = [path bounds];
		else bounds = NSMakeRect(0, 0, 0, 0);
		path = [self bouncingBallPathAtBeat: timeIndicatorPos];
		if (path != nil)
			bounds = NSUnionRect(bounds, [path bounds]);
		bounds = NSInsetRect(bounds, -1, -1);
		/*  Redraw the 'current' time indicator portion of each client view  */
		for (n = 0; n < myClientViewsCount; n++) {
			view = records[n].client;
			[view setNeedsDisplayInRect: [view convertRect: bounds fromView: myFloatingView]];
		}
		[[self window] discardCachedImage];
		timeIndicatorPos = -1.0;
		timeIndicatorRect = NSMakeRect(0, 0, 0, 0);
	}
}

- (void)showPlayPosition: (NSNotification *)notification
{
	NSRect visibleRect, documentRect;
	float beat = [[[notification userInfo] objectForKey: @"position"] floatValue];
	float pos = beat * [self pixelsPerQuarter];
	float width;

	{
		/*  If dragging in some client view, then don't autoscroll to play position  */
		GraphicClientView *lastView = [self lastMouseClientView];
		if (lastView != nil && [lastView isDragging])
			return;
		/*  If event tracking in this window, then don't autoscroll to play position  */
		if ([[[NSRunLoop currentRunLoop] currentMode] isEqualToString:NSEventTrackingRunLoopMode] && [[NSApp currentEvent] window] == [self window])
			return;
	}
	
//	fprintf(stderr, "showPlayPosition: beat = %f, pos = %f\n", beat, pos);
	if (pos < 0) {
		[self hideTimeIndicator];
		return;
	}
//	[myFloatingView setNeedsDisplay: YES];
	documentRect = [records[0].client frame];
	visibleRect = [[records[0].client superview] bounds];
	width = documentRect.size.width - visibleRect.size.width;
	if (pos < visibleRect.origin.x - documentRect.origin.x
	|| pos >= visibleRect.origin.x + visibleRect.size.width - documentRect.origin.x) {
		[self hideTimeIndicator];
		if (pos > width)
			pos = width;
		[myScroller setFloatValue: pos / width];
		[self scrollClientViewsToPosition: pos];
	//	visibleRect.origin.x = pos + documentRect.origin.x;
	//	[records[0].client scrollPoint: visibleRect.origin];
	}
	[self showTimeIndicatorAtBeat: beat];
}

/*
- (void)didStopPlaying: (NSNotification *)notification
{
	[self hideTimeIndicator];
}
*/

#pragma mark ==== Time marks ====

//  Calculate the intervals of vertical lines.
//    lineIntervalInPixels: the interval in pixels with which the vertical lines are to be drawn
//    mediumCount: every mediumCount lines, a vertical line with "medium thickness" appears
//    majorCount: every majorCount lines, a vertical line with "large thickness" appears
- (void)verticalLinesFromTick: (MDTickType)fromTick timeSignature: (MDEvent **)timeSignature nextTimeSignature: (MDEvent **)nextTimeSignature lineIntervalInPixels: (float *)lineIntervalInPixels mediumCount: (int *)mediumCount majorCount: (int *)majorCount
{
    MDTickType sTick, nsTick;
    float ppb;
    float interval;
    int mdCount, mjCount;
    MDEvent *ep1, *ep2;
    int sig0, sig1;
    if (myClientViewsCount > 0 && calib != NULL) {
        /*  Get time signature at fromTick  */
        MDCalibratorJumpToTick(calib, fromTick);
        ep1 = MDCalibratorGetEvent(calib, NULL, kMDEventTimeSignature, -1);
    } else {
        ep1 = NULL;
    }
    if (ep1 == NULL) {
        /*  Assume 4/4  */
        sig0 = sig1 = 4;
        sTick = 0;
    } else {
        const unsigned char *p = MDGetMetaDataPtr(ep1);
        sig0 = p[0];
        sig1 = (1 << p[1]);
        if (sig1 == 0)
            sig1 = 4;
        sTick = MDGetTick(ep1);
    }
    if (calib != NULL && (ep2 = MDCalibratorGetNextEvent(calib, NULL, kMDEventTimeSignature, -1)) != NULL)
        nsTick = MDGetTick(ep2);
    else {
        ep2 = NULL;
        nsTick = kMDMaxTick;
    }
    ppb = [self pixelsPerTick] * [[self document] timebase] * 4 / sig1;
    if (ppb * 0.125 >= kMinimumTickIntervalsInPixels) {
        interval = ppb * 0.125;
        mdCount = 4;
        mjCount = 8;
        while (interval >= kMinimumTickIntervalsInPixels * 2) {
            interval *= 0.5;
        }
    } else if (ppb * 0.5 >= kMinimumTickIntervalsInPixels) {
        interval = ppb * 0.5;
        mdCount = 2;
        mjCount = sig0 * mdCount;
        if (interval >= kMinimumTickIntervalsInPixels * 2) {
            interval *= 0.5;
            mdCount *= 2;
            mjCount *= 2;
        }
    } else if (ppb >= kMinimumTickIntervalsInPixels) {
        interval = ppb;
        mdCount = mjCount = sig0;
    } else {
        interval = ppb * sig0;
        mjCount = 5;
        while (interval < kMinimumTickIntervalsInPixels) {
            interval *= 10;
        }
        if (interval >= kMinimumTickIntervalsInPixels * 5) {
            interval *= 0.5;
            mjCount = 2;
        }
        mdCount = mjCount;
    }
    if (timeSignature)
        *timeSignature = ep1;
    if (nextTimeSignature)
        *nextTimeSignature = ep2;
    if (lineIntervalInPixels)
        *lineIntervalInPixels = interval;
    if (mediumCount)
        *mediumCount = mdCount;
    if (majorCount)
        *majorCount = mjCount;
}

- (void)convertTick: (MDTickType)aTick toMeasure: (long *)measure beat: (long *)beat andTick: (long *)tick
{
	MDCalibratorTickToMeasure(calib, aTick, measure, beat, tick);
}

- (void)editingRangeChanged: (NSNotification *)notification
{
	MDTickType startTick, endTick;
	NSTextField *tx1, *tx2;
	tx1 = (NSTextField *)[[[self window] contentView] viewWithTag: kEditingRangeStartTextTag];	
	tx2 = (NSTextField *)[[[self window] contentView] viewWithTag: kEditingRangeEndTextTag];	
	[(MyDocument *)[self document] getEditingRangeStart: &startTick end: &endTick];
	if (startTick < 0 || startTick >= kMDMaxTick) {
		[tx1 setStringValue: @""];
		[tx2 setStringValue: @""];
	} else {
		long startMeasure, startBeat, startSubTick;
		long endMeasure, endBeat, endSubTick;
		MDCalibratorTickToMeasure(calib, startTick, &startMeasure, &startBeat, &startSubTick);
		MDCalibratorTickToMeasure(calib, endTick, &endMeasure, &endBeat, &endSubTick);
		[tx1 setStringValue: [NSString stringWithFormat: @"%4ld:%2ld:%4ld", startMeasure, startBeat, startSubTick]];
		[tx2 setStringValue: [NSString stringWithFormat: @"%4ld:%2ld:%4ld", endMeasure, endBeat, endSubTick]];
	}
//	[tx setNeedsDisplay: YES];
	[self setNeedsReloadClientViews];
}

#pragma mark ==== Client views ====

- (void)adjustClientViewsInHeight: (float)aHeight
{
	//  Resize the client views (except for the top-most view = TimeChartView) so that
	// the total height becomes aHeight and the height proportion is preserved
	int i;
	float totalHeight, amountToResize, newHeight, splitterHeight;
	NSScrollView *scrollView;
//	NSView *rulerView;
	NSRect aFrame, frame, rFrame;
	float scrollerWidth, rulerWidth;

	if (myClientViewsCount == 0)
		return;

	scrollerWidth = [NSScroller scrollerWidth];
	rulerWidth = [self rulerWidth];

	//  Target rectangle
	aFrame = [myMainView bounds];
	aFrame.origin.x += rulerWidth;
	aFrame.size.width -= rulerWidth;
	aFrame.origin.y = aFrame.origin.y + aFrame.size.height - aHeight;
	aFrame.size.height = aHeight;
	rFrame = aFrame;
	rFrame.origin.x -= rulerWidth;
	rFrame.size.width = rulerWidth;

	//  Resize the TimeChartView (horizontal only)
	scrollView = [records[0].client enclosingScrollView];
	frame = [scrollView frame];
	frame.origin.y = (aFrame.origin.y + aFrame.size.height) - frame.size.height;
	frame.origin.x = aFrame.origin.x;
	frame.size.width = aFrame.size.width;
	if (![records[0].client hasVerticalScroller])
		frame.size.width -= scrollerWidth;
	[scrollView setFrame: frame];
//	[records[0].client reloadData];

	if (myClientViewsCount == 1) {
		[self setNeedsReloadClientViews];
		return;
	}

	//  Calculate the total height
	totalHeight = 0.0;
	splitterHeight = 0.0;
	for (i = 0; i < myClientViewsCount; i++) {
		totalHeight += [[records[i].client enclosingScrollView] frame].size.height;
		if (i > 0)
			splitterHeight += [records[i].splitter frame].size.height;
	}
	amountToResize = aHeight - (totalHeight + splitterHeight);
//	NSLog(@"totalHeight=%g, splitterHeight=%g, amountToResize=%g", totalHeight, splitterHeight, amountToResize);
	frame.size.width = aFrame.size.width;
	//  Resize
	for (i = myClientViewsCount - 1; i >= 1; i--) {

		//  Move the splitter view
		aFrame.origin.x -= rulerWidth;
		aFrame.size.width += rulerWidth;
		aFrame.size.height = [records[i].splitter frame].size.height;
		[records[i].splitter setFrame: aFrame];

		//  Resize the scroll view
		aFrame.origin.y += aFrame.size.height;
		aFrame.origin.x += rulerWidth;
		aFrame.size.width -= rulerWidth;
		scrollView = [records[i].client enclosingScrollView];
		if (i == 1) {
			aFrame.size.height = frame.origin.y - aFrame.origin.y;
		} else {
			newHeight = floor([scrollView frame].size.height * (1 + amountToResize / totalHeight) + 0.5);
			aFrame.size.height = newHeight;
		}
		aFrame.size.width = frame.size.width;
		if (![records[i].client hasVerticalScroller])
			aFrame.size.width -= scrollerWidth;
		[scrollView setFrame: aFrame];

		//  Resize the ruler view
	/*	rFrame.origin.y = aFrame.origin.y;
		rFrame.size.height = aFrame.size.height;
		if (records[i].ruler != nil) {
			[records[i].ruler setFrame: rFrame];
		} */

//		[records[i].client reloadData];
	
		aFrame.origin.y += aFrame.size.height;
	}
	
	[self setNeedsReloadClientViews];
}

- (void)updateTrackingRect
{
    NSRect bounds;
    NSPoint mouseLoc;
    if (trackingRectTag != 0)
        [myMainView removeTrackingRect: trackingRectTag];
    bounds = [myMainView bounds];
    mouseLoc = [myMainView convertPoint: [[self window] convertScreenToBase: [NSEvent mouseLocation]] fromView: nil];
    trackingRectTag = [myMainView addTrackingRect: bounds owner: self userData: nil assumeInside: NSMouseInRect(mouseLoc, bounds, [myMainView isFlipped])];
}

- (float)scrollPositionOfClientViews
{
    NSRect visibleRect, documentRect;
	if (myClientViewsCount == 0)
		return 0.0;
	visibleRect = [[records[0].client superview] bounds];
	documentRect = [records[0].client frame];
	return visibleRect.origin.x - documentRect.origin.x;
}

- (void)scrollClientViewsToPosition: (float)pos
{
    NSRect visibleRect, documentRect;
	int i;
    if (myClientViewsCount == 0)
        return;
    if (pos < 0)
        pos = 0;
	for (i = 0; i < myClientViewsCount; i++) {
		visibleRect = [[records[i].client superview] bounds];
		documentRect = [records[i].client frame];
		if (pos > documentRect.size.width)
			pos = documentRect.size.width;
		visibleRect.origin.x = documentRect.origin.x + pos;
		[records[i].client scrollPoint: visibleRect.origin];
	}
}

- (void)scrollClientViewsToTick: (MDTickType)tick
{
    [self scrollClientViewsToPosition: tick * [self pixelsPerTick]];
}

- (IBAction)scrollerMoved: (id)sender
{
	NSRect visibleRect, documentRect;
	NSScrollerPart hitPart;
	float pos, width, lineWidth;
//	NSLog(@"hitPart = %d", [sender hitPart]);
	if (myClientViewsCount == 0 || myScroller == nil)
		return;
	hitPart = [sender hitPart];
	pos = [sender floatValue];
	documentRect = [records[0].client frame];
	visibleRect = [[records[0].client superview] bounds];
	if (visibleRect.size.width > documentRect.size.width)
		return;
	width = documentRect.size.width - visibleRect.size.width;
	pos *= width;
	lineWidth = 32.0;
	if (lineWidth >= visibleRect.size.width * 0.5)
		lineWidth = visibleRect.size.width * 0.5;
	switch (hitPart) {
		case NSScrollerDecrementLine: pos -= lineWidth; break;
		case NSScrollerIncrementLine: pos += lineWidth; break;
		case NSScrollerDecrementPage: pos -= (visibleRect.size.width - lineWidth); break;
		case NSScrollerIncrementPage: pos += (visibleRect.size.width - lineWidth); break;
		default: break;
	}
	if (pos < 0)
		pos = 0.0;
	if (pos > width)
		pos = width;
	[myScroller setFloatValue: pos / width];
	pos = floor(pos);
	[self scrollClientViewsToPosition: pos];
//	visibleRect.origin.x = pos + documentRect.origin.x;
//	[records[0].client scrollPoint: visibleRect.origin];
}

- (void)zoomClientViewsWithPixelsPerQuarter:(float)ppq startingPos:(float)pos
{
	float oldppq = [self pixelsPerQuarter];
	float oldpos = [self scrollPositionOfClientViews];
	if (zoomUndoBuffer == nil) {
		zoomUndoBuffer = [[NSMutableArray allocWithZone:[self zone]] init];
	}
	if (zoomUndoIndex < [zoomUndoBuffer count] / 2)
		[zoomUndoBuffer removeObjectsInRange:NSMakeRange(zoomUndoIndex * 2, [zoomUndoBuffer count] - zoomUndoIndex * 2)];
	[zoomUndoBuffer addObject:[NSNumber numberWithFloat:oldppq]];
	[zoomUndoBuffer addObject:[NSNumber numberWithFloat:oldpos]];
	zoomUndoIndex++;
	[self setPixelsPerQuarter: ppq];
	[self scrollClientViewsToPosition: pos];
	[self reflectClientViews];
}

- (void)unzoomClientViews
{
	if (zoomUndoIndex > 0) {
		float oldppq = [self pixelsPerQuarter];
		float oldpos = [self scrollPositionOfClientViews];
		float ppq = [[zoomUndoBuffer objectAtIndex:zoomUndoIndex * 2 - 2] floatValue];
		float pos = [[zoomUndoBuffer objectAtIndex:zoomUndoIndex * 2 - 1] floatValue];
		[zoomUndoBuffer replaceObjectAtIndex:zoomUndoIndex * 2 - 2 withObject:[NSNumber numberWithFloat:oldppq]];
		[zoomUndoBuffer replaceObjectAtIndex:zoomUndoIndex * 2 - 1 withObject:[NSNumber numberWithFloat:oldpos]];
		zoomUndoIndex--;
		[self setPixelsPerQuarter:ppq];
		[self scrollClientViewsToPosition: pos];
		[self reflectClientViews];
	}
}

- (void)rezoomClientViews
{
	if (zoomUndoBuffer != nil && zoomUndoIndex < [zoomUndoBuffer count] / 2) {
		float oldppq = [self pixelsPerQuarter];
		float oldpos = [self scrollPositionOfClientViews];
		float ppq = [[zoomUndoBuffer objectAtIndex:zoomUndoIndex * 2] floatValue];
		float pos = [[zoomUndoBuffer objectAtIndex:zoomUndoIndex * 2 + 1] floatValue];
		[zoomUndoBuffer replaceObjectAtIndex:zoomUndoIndex * 2 withObject:[NSNumber numberWithFloat:oldppq]];
		[zoomUndoBuffer replaceObjectAtIndex:zoomUndoIndex * 2 + 1 withObject:[NSNumber numberWithFloat:oldpos]];
		zoomUndoIndex++;
		[self setPixelsPerQuarter:ppq];
		[self scrollClientViewsToPosition: pos];
		[self reflectClientViews];
	}
}

- (float)clientViewWidth
{
	float width = ([self sequenceDurationInQuarter] + 4.0) * [self pixelsPerQuarter];
	float minWidth = [myMainView bounds].size.width - [self rulerWidth] - [NSScroller scrollerWidth];
	if (width > minWidth)
		return width;
	else return minWidth;
}

- (void)reloadClientViews
{
	int i;
	for (i = 0; i < myClientViewsCount; i++) {
		[records[i].client reloadData];
	}
	[self reflectClientViews];

	/*  Redraw focus ring  */
    [myMainView setKeyboardFocusRingNeedsDisplayInRect: [myMainView bounds]];

	/*  Remove "NeedsReloadClientView" notifications  */
	[[NSNotificationQueue defaultQueue] dequeueNotificationsMatching: [NSNotification notificationWithName: sNeedsReloadClientViewNotification object: self] coalesceMask: NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender];
}

- (void)needsReloadClientViews: (NSNotification *)aNotification
{
	[self reloadClientViews];
}

- (void)setNeedsReloadClientViews
{
	/*  The "reload client" messages are coalesced and sent only once per event loop  */
	[[NSNotificationQueue defaultQueue] enqueueNotification: [NSNotification notificationWithName: sNeedsReloadClientViewNotification object: self] postingStyle: NSPostWhenIdle coalesceMask: NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender forModes: nil];
}

- (void)reflectClientViews
{
	NSRect visibleRect, documentRect;
	float pos, wid;
	if (myClientViewsCount == 0 || myScroller == nil)
		return;
	documentRect = [records[0].client frame];
	visibleRect = [[records[0].client superview] bounds];
	if (visibleRect.size.width >= documentRect.size.width) {
	/*	pos = 0.0;
		wid = 1.0; */
		[myScroller setEnabled: NO];
	} else {
		pos = (visibleRect.origin.x - documentRect.origin.x) / (documentRect.size.width - visibleRect.size.width);
		wid = visibleRect.size.width / documentRect.size.width;
		[myScroller setEnabled: YES];
		[myScroller setFloatValue: pos knobProportion: wid];
	}
}

/*
//  Adjust the client view frame when the enclosing scroll view is resized
- (void)superFrameDidChange: (NSNotification *)aNotification
{
	NSRect rect, newRect;
	int i;
	GraphicClientView *aView;
	id object = [aNotification object];
	return;
//	NSLog(@"superFrameDidChange from %@", object);
	for (i = 0; i < myClientViewsCount; i++) {
		aView = records[i].client;
		if ([aView superview] == object) {
			if (![aView hasVerticalScroller]) {
				rect = [object frame];
				newRect = [aView frame];
				newRect.size.height = rect.size.height;
				[aView setFrame: newRect];
				[aView reloadData];
				break;
			}
		}
	}
	//  Invalidate the cached image under the time indicator (if necessary)
	[self invalidateTimeIndicatorCachedImage];
    //  Update the tracking rect
    [self updateTrackingRect];
}
*/

/*
//  Adjust the scroll positions
- (void)superBoundsDidChange: (NSNotification *)aNotification
{
	NSRect rect, newRect;
	int i;
	GraphicClientView *aView;
	id object = [aNotification object];
	rect = [object bounds];
	for (i = 0; i < myClientViewsCount; i++) {
		aView = records[i].client;
		if (aView == nil)
			continue;
		if ([aView superview] != object) {
			newRect = [[aView superview] bounds];
			newRect.origin.x = rect.origin.x;
			[aView scrollPoint: newRect.origin];
		}
	}
	[self reflectClientViews];
	
	//  Invalidate the cached image under the time indicator (if necessary)
	[self invalidateTimeIndicatorCachedImage];
}
*/

/*  Customized autoresizing of clientviews  */
- (void)resizeClientViewsWithOldMainViewSize: (NSSize)oldSize
{
	NSSize newSize = [myMainView bounds].size;
//	NSLog(@"resizeClientViewsWithOldMainViewSize: newSize=%@, oldSize=%@", NSStringFromSize(newSize), NSStringFromSize(oldSize));
	[self adjustClientViewsInHeight: newSize.height];
}

/*
//  myMainView has changed size
- (void)myMainViewFrameDidChange: (NSNotification *)aNotification
{
	//  Vertical
	
	//  Horizontal
	//  Resize the client views if necessary
//	[self reloadClientViews];
}
*/

/*
//  Adjust the content frame sizes
- (void)frameDidChange: (NSNotification *)aNotification
{
	NSRect rect, newRect;
	int i;
//	float newXScale;
	GraphicClientView *aView;
	id object = [aNotification object];
//	NSLog(@"frameDidChange");
	rect = [object bounds];
//	if ([object respondsToSelector: @selector(xScale)])
//		newXScale = [object xScale];
//	else newXScale = -1;
	for (i = 0; i < myClientViewsCount; i++) {
		aView = records[i].client;
		if (aView != nil && object != aView) {
		//	if (newXScale != -1 && [aView xScale] != newXScale)
		//		[aView setXScale: newXScale];
			newRect = [aView frame];
			newRect.size.width = rect.size.width;
			[aView setFrame: newRect];
		}
	}
	[self reflectClientViews];
}
*/

/*
//  Register notification with a client view
- (void)registerNotificationWithView: (GraphicClientView *)view
{
	return;
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(superBoundsDidChange:)
		name: NSViewBoundsDidChangeNotification
		object: [view superview]];
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(superFrameDidChange:)
		name: NSViewFrameDidChangeNotification
		object: [view superview]];
	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(frameDidChange:)
		name: NSViewFrameDidChangeNotification
		object: view];
	
	[[view superview] setPostsBoundsChangedNotifications: YES];
//	[[view superview] setPostsFrameChangedNotifications: YES];
	[view setPostsFrameChangedNotifications: YES];
}
*/

/*
//  Unregister notification with a client view
- (void)unregisterNotificationWithView: (GraphicClientView *)view
{
	return;
#if 0
	[[NSNotificationCenter defaultCenter]
		removeObserver: self
		name: nil
		object: [view superview]];
	[[NSNotificationCenter defaultCenter]
		removeObserver: self
		name: nil
		object: view];
#endif
}
*/

- (void)limitWindowSize
{
	float windowHeight, currentHeight, limitHeight;
	int i;
	NSWindow *window = [self window];
	NSSize minSize = [window minSize];
	windowHeight = [window frame].size.height;
	currentHeight = limitHeight = 0;
	for (i = 0; i < myClientViewsCount; i++) {
		limitHeight += [[records[i].client class] minHeight];
		currentHeight += [[records[i].client enclosingScrollView] frame].size.height;
	}
	minSize.height = windowHeight - (currentHeight - limitHeight);
	[window setMinSize: minSize];
//	NSLog(@"limitWindowSize %@", NSStringFromSize(minSize));
}

- (void)createClientViewWithClasses: (id)chartClass : (id)rulerClass
{
	NSScrollView *scrollView;
	NSClipView *clipView;
	GraphicClientView *clientView;
	GraphicRulerView *rulerView;
	GraphicSplitterView *splitterView;
	NSRect aRect, rect;
	float scrollerWidth, rulerWidth, height, splitterHeight, minHeight;
	unsigned int mask;

	if (myClientViewsCount >= kGraphicWindowControllerMaxNumberOfClientViews)
		return;   //  Too many client views
	
	aRect = [myMainView bounds];
	scrollerWidth = [NSScroller scrollerWidth];
	minHeight = [chartClass minHeight];

	if (myClientViewsCount == 0) {
		height = minHeight;
		aRect.origin.y += (aRect.size.height - height);
		aRect.size.height = height;
		mask = NSViewMinYMargin;
	} else {
		scrollView = [records[myClientViewsCount - 1].client enclosingScrollView];
		if (myClientViewsCount == 1) {
			rect = [scrollView frame];
			splitterHeight = 4.0;
			mask = NSViewHeightSizable;
		} else {
			rect = [records[myClientViewsCount - 1].splitter frame];
			splitterHeight = 16.0;
			mask = NSViewMaxYMargin;
		}
		height = rect.origin.y - aRect.origin.y - splitterHeight;
		if (height < minHeight) {
			height = minHeight;
			[self adjustClientViewsInHeight: aRect.size.height - (height + splitterHeight)];
		}
		aRect.size.height = height;
		aRect.origin.y += splitterHeight;
	}

	//  Create the chart view
	//  NSScrollView
	rulerWidth = [self rulerWidth];
	rect = aRect;
	rect.size.width -= rulerWidth;
	rect.origin.x += rulerWidth;
	scrollView = [[[NSScrollView allocWithZone: [self zone]] initWithFrame: rect] autorelease];
	[myMainView addSubview: scrollView];
	[scrollView setAutoresizingMask: (NSViewWidthSizable | mask)];
	[scrollView setHasHorizontalScroller: NO];
//	[scrollView setHorizontalScroller: myScroller];

	//  The chart view
	rect.origin.x = rect.origin.y = 0.0;
//	rect.size.height -= scrollerWidth;
	//  Don't autorelease, since we are going to retain it
	clientView = [[chartClass allocWithZone: [self zone]] initWithFrame: rect];
	[scrollView setDocumentView: clientView];
	if ([clientView hasVerticalScroller]) {
		[scrollView setHasVerticalScroller: YES];
	} else {
		[scrollView setHasVerticalScroller: NO];
		rect = [scrollView frame];
		rect.size.width -= scrollerWidth;
		[scrollView setFrame: rect];
	}
	[clientView setDataSource: self];
//	if (myClientViewsCount == 0)
//		[clientView setXScale: 72 / 2.54];  /*  1 cm per quarter note */
//	else
//		[clientView setXScale: [records[0].client xScale]];
//	[self registerNotificationWithView: clientView];
	records[myClientViewsCount].client = clientView;
	
	if (myClientViewsCount > 0 && rulerClass != nil) {
		//  Create the ruler view
		//  NSClipView
		rect = aRect;
		rect.size.width = rulerWidth;
	//	rect.origin.y += scrollerWidth;
	//	rect.size.height -= scrollerWidth;
		clipView = [[[NSClipView allocWithZone: [self zone]] initWithFrame: rect] autorelease];
		[myMainView addSubview: clipView];
		[clipView setAutoresizingMask: (NSViewMaxXMargin | mask)];
		
		//  The chart view
		rect.origin.x = rect.origin.y = 0.0;
		rulerView = [[rulerClass allocWithZone: [self zone]] initWithFrame: rect];
		[clipView setDocumentView: rulerView];
		[rulerView setClientView: clientView];
		records[myClientViewsCount].ruler = rulerView;
	}

	if (myClientViewsCount > 0) {
		//  Create the splitter view
		rect = aRect;
		rect.origin.y -= splitterHeight;
		rect.size.height = splitterHeight;
		splitterView = [[GraphicSplitterView allocWithZone: [self zone]] initWithFrame: rect];
		[myMainView addSubview: splitterView];
		[splitterView setAutoresizingMask: (NSViewWidthSizable | NSViewMaxYMargin)];
		records[myClientViewsCount].splitter = splitterView;
	}
	
/*
	if ([clientView isKindOfClass: [TimeChartView class]]) {
		records[myClientViewsCount].calib =
			MDCalibratorNew([[[self document] myMIDISequence] mySequence], NULL, kMDEventTimeSignature, -1);
	} else {
		records[myClientViewsCount].calib = NULL;
	}
*/
	
	myClientViewsCount++;
	
	if ([clientView isKindOfClass: [StripChartView class]]) {
		[self setStripChartAtIndex: myClientViewsCount - 1 kind: kMDEventNote code: 0];
	}
	
	[clientView reloadData];
	
	[self limitWindowSize];
}

- (void)collapseClientViewAtIndex: (int)index
{
	int i;
	NSRect frame;
	float y;
	frame = [[records[index].client enclosingScrollView] frame];
	y = frame.origin.y + frame.size.height;
	[[records[index].client enclosingScrollView] removeFromSuperview];
	[[records[index].ruler superview] removeFromSuperview];
	[records[index].splitter removeFromSuperview];
//	[self unregisterNotificationWithView: records[index].client];
	[records[index].client autorelease];
	[records[index].ruler autorelease];
	[records[index].splitter autorelease];
/*	if (records[index].calib != NULL)
		MDCalibratorRelease(records[index].calib); */
	for (i = index; i < myClientViewsCount - 1; i++) {
		records[i] = records[i + 1];
	}
	memset(&records[i], 0, sizeof(records[i]));
	myClientViewsCount--;
	if (index < myClientViewsCount) {
		frame = [[records[index].client enclosingScrollView] frame];
		frame.size.height = y - frame.origin.y;
		[[records[index].client enclosingScrollView] setFrame: frame];
	} else if (index > 1) {
		y = [myMainView bounds].origin.y;
		frame = [records[index - 1].splitter frame];
		frame.origin.y = y;
		[records[index - 1].splitter setFrame: frame];
		y += frame.size.height;
		frame = [[records[index - 1].client enclosingScrollView] frame];
		frame.size.height = frame.origin.y + frame.size.height - y;
		frame.origin.y = y;
		[[records[index - 1].client enclosingScrollView] setFrame: frame];
	}
	[self setNeedsReloadClientViews];
	[myMainView setNeedsDisplay: YES];
	[self limitWindowSize];
}

- (void)splitterView: (GraphicSplitterView *)theView isDraggedTo: (float)y confirm: (BOOL)confirm
{
	int index;
	NSScrollView *scrollView;
	NSRect frame_above, frame_self, frame_below;
	float ymax, ymin;
	for (index = 1; index < myClientViewsCount; index++) {
		if (records[index].splitter == theView)
			break;
	}
	if (index == myClientViewsCount) {
	//	NSLog(@"splitterView:isDraggedBy:confirm: theView (%@) not found", theView);
		return;
	}
//	[self setInfoText: [NSString stringWithFormat: @"y = %g", y]];
	frame_above = [[records[index].client enclosingScrollView] frame];
	frame_self  = [records[index].splitter frame];
	ymax = frame_above.origin.y + frame_above.size.height - frame_self.size.height;
	if (index == 1) {
		//  Piano roll view cannot be collapsed
		if (y >= ymax - 32.0)
			y = ymax - 32.0;
	}
	if (y >= ymax) {
		y = ymax;
		if (confirm) {
			//  Collapse this client
			[self collapseClientViewAtIndex: index];
			return;
		}
	}
	if (confirm && y >= ymax - 32.0) {
		//  Avoid too narrow strip chart
		y = ymax - 32.0;
	}
	if (index < myClientViewsCount - 1) {
		scrollView = [records[index + 1].client enclosingScrollView];
		frame_below = [scrollView frame];
		ymin = frame_below.origin.y;
	} else {
		scrollView = nil;
		ymin = [myMainView bounds].origin.y;
	}
	if (y <= ymin) {
		y = ymin;
		if (confirm && index < myClientViewsCount - 1) {
			//  Collapse the lowest client
			[self collapseClientViewAtIndex: index + 1];
			return;
		}
	}
	if (confirm && index < myClientViewsCount - 1 && y <= ymin + 32.0) {
		//  Avoid too narrow strip chart
		y = ymin + 32.0;
	}
	frame_above.origin.y = y + frame_self.size.height;
	frame_above.size.height = ymax - y;
	[[records[index].client enclosingScrollView] setFrame: frame_above];
	[[records[index].client enclosingScrollView] setNeedsDisplay: YES];
	[records[index].client reloadData];
	frame_self.origin.y = y;
	[records[index].splitter setFrame: frame_self];
	[records[index].splitter setNeedsDisplay: YES];
	if (scrollView != nil) {
		frame_below.size.height = y - ymin;
		[scrollView setFrame: frame_below];
		[scrollView setNeedsDisplay: YES];
		[records[index + 1].client reloadData];
	} else if (confirm && y > ymin) {
		//  Create a new client view
		[self createClientViewWithClasses: [StripChartView class] : [StripChartRulerView class]];
		//  Scroll to the current position
		[self scrollClientViewsToPosition: [self scrollPositionOfClientViews]];
	//	[self superBoundsDidChange:
	//		[NSNotification notificationWithName: NSViewBoundsDidChangeNotification
	//			object: [records[0].client superview]]];
			//  Simulate scroll to force recalculation of the scroll position
	}
	if (confirm)
		[myMainView display];
	else {
        if (scrollView == nil) {
            NSRect theRect = [myMainView bounds];
            theRect.size.height = y - ymin;
            [myMainView lockFocus];
            NSDrawWindowBackground(theRect);
            [myMainView unlockFocus];
        }
		[myMainView displayIfNeeded];
    }
}

- (void)setStripChartAtIndex: (int)index kind: (int)kind code: (int)code
{
	long kindAndCode;
	MDSequence *sequence;
	int newKind;
    dprintf(1, "setStripChartAtIndex: %d %d %d\n", index, kind, code);
	if (![records[index].client isKindOfClass: [StripChartView class]])
		return;
	if (kind < 0 && code < 0)
		return;
	if (kind < 0)
		newKind = ([(StripChartView *)records[index].client kindAndCode] >> 16) & 65535;
	else
		newKind = kind;
    if (newKind == kMDEventControl) {
        if (code < 0)
            code = 11;	//  Expression
    } else if (newKind == kMDEventKeyPres) {
        if (code < 0)
            code = 60;	//  Central C
    } else code = -1;

/*	if (records[index].calib != NULL)
		MDCalibratorRelease(records[index].calib); */
	sequence = [[[self document] myMIDISequence] mySequence];
/*
	if (newKind == kMDEventTempo) {
		calib = MDCalibratorNew(sequence, NULL, newKind, -1);
	} else {
		for (n = 1; n < MDSequenceGetNumberOfTracks(sequence); n++) {
			track = MDSequenceGetTrack(sequence, n);
			if (n == 1) {
				calib = MDCalibratorNew(sequence, track, newKind, code);
			} else {
				MDCalibratorAppend(calib, track, newKind, code);
			}
		}
	}
	records[index].calib = calib;
*/
	kindAndCode = ((kind & 65535) << 16) | (code & 65535);
	[(StripChartView *)records[index].client setKindAndCode: kindAndCode];
	[records[index].splitter setKindAndCode: kindAndCode];
	[records[index].ruler setNeedsDisplay: YES];
}

- (IBAction)kindPopUpPressed: (id)sender
{
	int i, kind;
	for (i = 1; i < myClientViewsCount; i++) {
		if (records[i].splitter == (GraphicSplitterView *)[sender superview]) {
			kind = [[sender selectedItem] tag];
			[self setStripChartAtIndex: i kind: kind code: -1];
			break;
		}
	}
}

- (IBAction)codeMenuItemSelected: (id)sender
{
	int i, code;
	NSView *focus;
	code = [sender tag];
	focus = [NSView focusView];
	for (i = 1; i < myClientViewsCount; i++) {
		if ([focus isDescendantOf: records[i].splitter]) {
			[self setStripChartAtIndex: i kind: -1 code: code];
			break;
		}
	}
}

- (IBAction)expandHorizontally: (id)sender
{
    float ppq = [self pixelsPerQuarter];
	float pos = [self scrollPositionOfClientViews];
	[self zoomClientViewsWithPixelsPerQuarter:ppq * 2 startingPos:pos * 2];
//	[self reloadClientViews];
//	[self reflectClientViews];
/*    NSRect documentRect, visibleRect;
    if (myClientViewsCount == 0)
        return;
	documentRect = [records[0].client frame];
	visibleRect = [[records[0].client superview] bounds];
    ppq = pixelsPerQuarter;
    r = documentRect.size.width / visibleRect.size.width;
    if (r < 1)
        return;
    else if (r < 2)
        ppq *= r;
    else ppq *= 2;
    [self setPixelsPerQuarter: ppq]; */
}

- (IBAction)shrinkHorizontally: (id)sender
{
    float ppq, r, pos;
    NSRect documentRect, visibleRect;
    if (myClientViewsCount == 0)
        return;
	documentRect = [records[0].client frame];
	visibleRect = [[records[0].client superview] bounds];
    ppq = pixelsPerQuarter;
    r = documentRect.size.width / visibleRect.size.width;
    if (r < 1)
        return;
    else if (r >= 2)
		r = 2;
	pos = [self scrollPositionOfClientViews];
	[self zoomClientViewsWithPixelsPerQuarter:ppq / r startingPos:pos / r];
//	[self reloadClientViews];
//	[self reflectClientViews];
/*    [self setPixelsPerQuarter: ppq / 2]; */
}

- (GraphicClientView *)clientViewAtIndex: (int)index
{
	if (index >= 0 && index < myClientViewsCount)
		return records[index].client;
	else return nil;
}

/*  Used by GraphicBackgroundView to send key events to the active client view  */
- (void)mouseEvent:(NSEvent *)theEvent receivedByClientView:(GraphicClientView *)cView
{
	int i;
	for (i = 0; i < myClientViewsCount; i++) {
		if (records[i].client == cView) {
			lastMouseClientViewIndex = i;
			return;
		}
	}
	lastMouseClientViewIndex = -1;
}

- (GraphicClientView *)lastMouseClientView
{
	if (lastMouseClientViewIndex >= 0 && lastMouseClientViewIndex < myClientViewsCount)
		return records[lastMouseClientViewIndex].client;
	else return nil;
}

#pragma mark ==== Window info ====

/*  Update the device menu popup  */
static void
sUpdateDeviceMenu(MyComboBoxCell *cell)
{
	int i, n;
	id currentValue = [cell objectValueOfSelectedItem];
	[cell removeAllItems];
	[cell addItemWithObjectValue: @""];
	n = MDPlayerGetNumberOfDestinations();
	for (i = 0; i < n; i++) {
		char name[64];
		MDPlayerGetDestinationName(i, name, sizeof name);
		[cell addItemWithObjectValue: [NSString localizedStringWithFormat: @"%s", name]];
	}
	[cell selectItemWithObjectValue: currentValue];
}

/*  Update the device menu when MIDI setup is changed  */
- (void)midiSetupDidChange: (NSNotification *)aNotification
{
	NSTableColumn *tableColumn;
	MyComboBoxCell *cell;
	tableColumn = [myTableView tableColumnWithIdentifier: sTableColumnIDs[kDeviceNameID]];
	cell = (MyComboBoxCell *)[tableColumn dataCell];
	sUpdateDeviceMenu(cell);
}

- (void)windowDidLoad
{
	NSTableColumn *tableColumn;
    NSCell *cell;
	NSFont *font;
	NSEnumerator *enumerator;
//	NSView *view;
	NSRect frame, bounds;
	int i;

	[super windowDidLoad];
	
    /*  Accepts the mouse move events  */
    [[self window] setAcceptsMouseMovedEvents: YES];

	/*  Register the notification  */
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(trackModified:)
		name:MyDocumentTrackModifiedNotification
		object:[self document]];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(showPlayPosition:)
		name:MyDocumentPlayPositionNotification
		object:[self document]];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(trackInserted:)
		name:MyDocumentTrackInsertedNotification
		object:[self document]];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(trackDeleted:)
		name:MyDocumentTrackDeletedNotification
		object:[self document]];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(trackModified:)
		name:MyDocumentSelectionDidChangeNotification
		object:[self document]];

	[[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(needsReloadClientViews:)
		name: sNeedsReloadClientViewNotification
		object: self];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(editingRangeChanged:)
		name:MyDocumentEditingRangeDidChangeNotification
		object:[self document]];

//	[[NSNotificationCenter defaultCenter]
//		addObserver: self
//		selector: @selector(myMainViewFrameDidChange:)
//		name: NSViewFrameDidChangeNotification
//		object: myMainView];
	[myMainView setPostsFrameChangedNotifications: YES];

/*	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(showPlayPosition:)
		name:MyDocumentStopPlayingNotification
		object:[self document]];
*/

	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(midiSetupDidChange:)
	 name:MyAppControllerMIDISetupDidChangeNotification
	 object:[NSApp delegate]];
	
    calib = MDCalibratorNew([[[self document] myMIDISequence] mySequence], NULL, kMDEventTimeSignature, -1);

	/*  Set pixels per tick: about 1 cm per quarter note  */
	[self setPixelsPerQuarter: 72 / 2.54];
	
	/*  Create the time chart ruler  */
	[self createClientViewWithClasses: [TimeChartView class] : nil];
	
	/*  Create the piano roll view  */
	[self createClientViewWithClasses: [PianoRollView class] : [PianoRollRulerView class]];
	
	/*  Create the strip chart view  */
	[self adjustClientViewsInHeight: floor([myMainView bounds].size.height * 0.75)];
	[self createClientViewWithClasses: [StripChartView class] : [StripChartRulerView class]];

	/*  Set the default scale factor for the piano-roll view  */
	[records[1].client setYScale: 7.0];        /*  7 pixels per half-tone */
//	[records[1].client reloadData];

	/*  Center the piano-roll view vertically  */
	frame = [records[1].client frame];
	bounds = [[records[1].client superview] bounds];
	if (frame.size.height > bounds.size.height) {
		bounds.origin.y = (frame.size.height - bounds.size.height) / 2;
		[records[1].client scrollPoint: bounds.origin];
	}

	[myScroller setEnabled: YES];

    /*  Set myTableView as the initial first responder  */
    [[self window] setInitialFirstResponder: myTableView];
    
	/*  Set up the data cells for the TableView  */
	{
		font = [NSFont systemFontOfSize: [NSFont smallSystemFontSize]];

	/*	tableColumn = [myTableView tableColumnWithIdentifier: sTableColumnIDs[kVisibleID]];
		cell = [[[NSButtonCell alloc] init] autorelease];
		[(NSButtonCell *)cell setButtonType: NSSwitchButton];
		[cell setControlSize: NSSmallControlSize];
		[tableColumn setDataCell: cell]; */

		if (sPencilSmallImage == NULL)
			sPencilSmallImage = [[NSImage imageNamed: @"pencil_small.png"] retain];
		if (sEyeOpenImage == NULL)
			sEyeOpenImage = [[NSImage imageNamed: @"eye_open.png"] retain];
		if (sEyeCloseImage == NULL)
			sEyeCloseImage = [[NSImage imageNamed: @"eye_close.png"] retain];
		if (sSpeakerImage == NULL)
			sSpeakerImage = [[NSImage imageNamed: @"speaker.png"] retain];
		if (sSpeakerGrayImage == NULL)
			sSpeakerGrayImage = [[NSImage imageNamed: @"speaker_gray.png"] retain];
		if (sMuteImage == NULL)
			sMuteImage = [[NSImage imageNamed: @"mute.png"] retain];
		if (sMuteNonImage == NULL)
			sMuteNonImage = [[NSImage imageNamed: @"mute_non.png"] retain];
		if (sSoloImage == NULL)
			sSoloImage = [[NSImage imageNamed: @"solo.png"] retain];
		if (sSoloNonImage == NULL)
			sSoloNonImage = [[NSImage imageNamed: @"solo_non.png"] retain];
		
		for (i = 0; i < 4; i++) {
			static int s[] = {kEditableID, kVisibleID, kSoloID, kMuteID};
		//	static NSString *n[] = {@"pencil_small.png", @"eye_open.png", @"speaker.png"};
			NSImage *im[] = {sPencilSmallImage, sEyeOpenImage, sSoloImage, sSpeakerImage};
			tableColumn = [myTableView tableColumnWithIdentifier: sTableColumnIDs[s[i]]];
			cell = [[[ColorCell alloc] init] autorelease];
			[cell setTarget: self];
		//	[cell setAction: @selector(trackTableAction:)];
			[cell setImage: im[i]];
			if (s[i] == kSoloID) {
				[cell setRepresentedObject:[NSColor colorWithDeviceRed:1.0 green:1.0 blue:0.3 alpha:1.0]];
				[(ColorCell *)cell setStrokesColor:NO];
			}
			[tableColumn setDataCell: cell];
			[[tableColumn headerCell] setImage: im[i]];
		}

		[myTableView setAction: @selector(trackTableAction:)];
		[myTableView setDoubleAction: @selector(trackTableDoubleAction:)];
		
	/*	tableColumn = [myTableView tableColumnWithIdentifier: @"attribute"];
		cell = [[[TrackAttributeCell alloc] init] autorelease];
		[cell setAction: @selector(trackTableAction:)];
		[tableColumn setDataCell: cell]; */

		tableColumn = [myTableView tableColumnWithIdentifier: sTableColumnIDs[kChannelID]];
		cell = [[[MyPopUpButtonCell alloc] initTextCell: @"-" pullsDown: NO] autorelease];
		[cell setBordered: NO];
		[cell setFont: font];
		for (i = 1; i <= 16; i++) {
			[(NSPopUpButtonCell *)cell addItemWithTitle: [NSString stringWithFormat: @"%d", i]];
		}
		[tableColumn setDataCell: cell];

		tableColumn = [myTableView tableColumnWithIdentifier: sTableColumnIDs[kDeviceNameID]];
		cell = [[[MyComboBoxCell alloc] init] autorelease];
		[cell setEditable: YES];
		[cell setFont: font];
		[cell setBordered: NO];
		[cell setControlSize: NSSmallControlSize];
		[(MyComboBoxCell *)cell setCompletes: YES];
		sUpdateDeviceMenu((MyComboBoxCell *)cell);
		[(MyComboBoxCell *)cell setControlView: myTableView];
		[tableColumn setDataCell: cell];

		[myTableView setRowHeight: [font defaultLineHeightForFont]];
		enumerator = [[myTableView tableColumns] objectEnumerator];
		while ((tableColumn = (NSTableColumn *)[enumerator nextObject]) != nil) {
			[[tableColumn dataCell] setFont: font];
		}
	}
	
	{
		MyMIDISequence *seq = [[self document] myMIDISequence];
		/*  Select the editable flag: only the first non-conductor track is made editable  */
		for (i = [seq trackCount] - 1; i >= 0; i--) {
			MDTrackAttribute attr = [seq trackAttributeAtIndex: i];
			if (i == 1)
				attr |= kMDTrackAttributeEditable;
			else
				attr &= ~kMDTrackAttributeEditable;
			[seq setTrackAttribute: attr atIndex: i];
		}
	}
	
	/*  Resize the buttons for small icons (to work around bug? of IB)  */
	/*  2006.1.2. This looks no longer necessary.  */
/*	view = [[[self window] contentView] viewWithTag: kPlusButtonTag];
	frame = [view frame];
	frame.size.height = 16;
	[view setFrame: frame];
	view = [[[self window] contentView] viewWithTag: kMinusButtonTag];
	frame = [view frame];
	frame.size.height = 16;
	[view setFrame: frame];
	view = [[[self window] contentView] viewWithTag: kShrinkButtonTag];
	frame = [view frame];
	frame.size.height = 16;
	[view setFrame: frame];
	view = [[[self window] contentView] viewWithTag: kExpandButtonTag];
	frame = [view frame];
	frame.size.height = 16;
	[view setFrame: frame];  */

	/*  Set up the popup menus  */
	{
		/*  Shape popup menu  */
		id myPopUpButton = [[[self window] contentView] viewWithTag: kShapePopUpTag];
		id menuItem;
		NSMenu *menu;
		NSString *imageName;
		NSImage *anImage;
		int i, itag;
		/*  Resize the popup menu; the Interface Builder did not allow me to create
		    a popup button with shadowless bezel style, so I use the normal popup button
			and change it into shadowless one programatically. The problem is that
			the "mini" popup button has the fixed 15-pixel height. As a workaround,
			the height is also set programatically.  */
		frame = [myPopUpButton frame];
		frame.size.height = 16;
		[myPopUpButton setFrame: frame];
		[myPopUpButton setBezelStyle: NSShadowlessSquareBezelStyle];
		[myPopUpButton setImagePosition: NSNoImage];
		/*  Set images  */
		for (i = [myPopUpButton numberOfItems] - 1; i >= 0; i--) {
			menuItem = [myPopUpButton itemAtIndex: i];
			switch ([menuItem tag]) {
				case kLinearMenuTag: imageName = @"linear.png"; break;
				case kParabolaMenuTag: imageName = @"parabola.png"; break;
				case kArcMenuTag: imageName = @"arc.png"; break;
				case kSigmoidMenuTag: imageName = @"sigmoid.png"; break;
				case kRandomMenuTag: imageName = @"random.png"; break;
				default: imageName = nil; break;
			}
			if (imageName != nil) {
				anImage = [NSImage imageNamed: imageName];
				[menuItem setImage: anImage];
			}
		}
		
		/*  Mode popup menu  */
		myPopUpButton = [[[self window] contentView] viewWithTag: kModePopUpTag];
		frame = [myPopUpButton frame];
		frame.size.height = 16;
		[myPopUpButton setFrame: frame];
		[myPopUpButton setBezelStyle: NSShadowlessSquareBezelStyle];
		
		graphicTool = kGraphicSelectTool;
		graphicLineShape = kGraphicLinearShape;
		graphicEditingMode = kGraphicSetMode;
		
		/*  Quantize popup menu  */
		myPopUpButton = [[[self window] contentView] viewWithTag: kQuantizePopUpTag];
		frame = [myPopUpButton frame];
		frame.size.height = 16;
		[myPopUpButton setFrame: frame];
		[myPopUpButton setBezelStyle: NSShadowlessSquareBezelStyle];
		menu = [myPopUpButton menu];
		[[menu itemAtIndex: 0] setImage: [NSImage imageNamed: @"NQ.png"]];
	//	while ([menu numberOfItems] > 0)
	//		[menu removeItemAtIndex: 0];
		itag = kQuantizeMenuTag + 1;
		for (i = 0; i < 3; i++) {
			static NSString *fmt[] = {@"note%d.png", @"note%dd.png", @"note%d_3.png"};
			int j;
			for (j = 1; j <= 32; j *= 2) {
				menuItem = [[[NSMenuItem allocWithZone: [self zone]] initWithTitle: @"" action: @selector(quantizeSelected:) keyEquivalent: @""] autorelease];
				[menuItem setImage: [NSImage imageNamed: [NSString stringWithFormat: fmt[i], j]]];
				[menuItem setTag: itag];
				[menu addItem: menuItem];
				itag++;
			}
		}
	}

	/*  Initialize the playing view  */
	[playingViewController windowDidLoad];
	
	[self reloadClientViews];
    [self updateTrackingRect];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
#if 1
	return displayName;
#else
	if (myTrack != NULL) {
		char buf[256];
		MDTrackGetName(myTrack, buf, sizeof buf);
	//	NSLog(@"Track name = %s\n", buf);
		return [NSString stringWithFormat:@"Graphic:%@:%s", displayName, buf];
	} else return displayName;
#endif
}

- (MDTickType)sequenceDuration
{
	return [[[self document] myMIDISequence] sequenceDuration];
}

- (float)sequenceDurationInQuarter
{
	return (float)[self sequenceDuration] / [[self document] timebase];
}

- (void)setInfoText: (NSString *)string
{
	[[[[self window] contentView] viewWithTag: kInfoTextTag] setStringValue: string];
}

- (void)changeFirstResponderWithEvent: (NSEvent *)theEvent
{
	/*  myTableView, myMainView, or myPlayerView will be the first responder  */
	NSPoint pt = [theEvent locationInWindow];
	NSWindow *theWindow = [self window];
	id obj = [theWindow firstResponder];
	NSRect frame;
	
	if ([obj isKindOfClass: [NSActionCell class]]) {
		obj = [obj controlView];
	} else if (obj == [theWindow fieldEditor: NO forObject: nil]) {
		obj = [obj delegate];
	}
	if ([obj isKindOfClass: [NSView class]]) {
		frame = [[obj superview] convertRect: [obj frame] toView: nil];
		//  Don't change focus if clicked on itself
		if (NSPointInRect(pt, frame))
			return;
	}
	
	if (NSPointInRect(pt, [[myMainView superview] convertRect: [myMainView frame] toView: nil])) {
		[theWindow makeFirstResponder: myMainView];
	} else if (NSPointInRect(pt, [[myPlayerView superview] convertRect: [myPlayerView frame] toView: nil])) {
		[theWindow makeFirstResponder: myPlayerView];
	}	
}

/*
- (BOOL)shouldResignFirstResponderInWindow: (NSWindow *)theWindow withEvent: (NSEvent *)theEvent
{
	//  Unfocus TextField when myMainView or myPlayerView is clicked
	NSPoint pt = [theEvent locationInWindow];
	id obj = [theWindow firstResponder];
	NSRect frame;
	if ([obj isKindOfClass: [NSTextFieldCell class]]) {
		obj = [obj controlView];
	} else if (![obj isKindOfClass: [NSTextField class]] && ![obj isKindOfClass: [NSTextView class]]) {
		return NO;
	}
	frame = [[obj superview] convertRect: [obj frame] toView: nil];

	//  Don't unfocus if clicked on itself
	if (NSPointInRect(pt, frame))
		return NO;

	if (NSPointInRect(pt, [[myMainView superview] convertRect: [myMainView frame] toView: nil])
	|| NSPointInRect(pt, [[myPlayerView superview] convertRect: [myPlayerView frame] toView: nil])
	|| NSPointInRect(pt, [[myToolbarView superview] convertRect: [myToolbarView frame] toView: nil]))
		return YES;
	else return NO;
}
*/

- (id)playingViewController
{
	return playingViewController;
}

#pragma mark ==== Editing operation in ClientViews ====

- (NSColor *)colorForTrack: (int)track enabled: (BOOL)flag
{
	return [[self document] colorForTrack: track enabled: flag];
}

- (void)dragNotesByTick: (MDTickType)deltaTick andNote: (int)deltaNote sender: (GraphicClientView *)sender optionFlag: (BOOL)optionFlag
{
    int i, n, track;
    MDSelectionObject *pointSet;
    MyDocument *document = [self document];
    n = [self visibleTrackCount];
	if (optionFlag && (deltaTick != 0 || deltaNote != 0)) {
		//  Duplicate notes
        for (i = 0; i < n; i++) {
            track = [self sortedTrackNumberAtIndex: i];
            if (track < 0)
                continue;
            pointSet = [document selectionOfTrack: track];
            if (pointSet == nil || MDPointSetGetCount([pointSet pointSet]) <= 0)
                continue;
			[document duplicateMultipleEventsAt: pointSet ofTrack: track selectInsertedEvents: YES];
		}
	}
    if (deltaTick != 0) {
        NSNumber *deltaTickNum = [NSNumber numberWithLong: deltaTick];
        for (i = 0; i < n; i++) {
            track = [self sortedTrackNumberAtIndex: i];
            if (track < 0)
                continue;
            pointSet = [document selectionOfTrack: track];
            if (pointSet == nil || MDPointSetGetCount([pointSet pointSet]) <= 0)
                continue;
            [document modifyTick: deltaTickNum ofMultipleEventsAt: pointSet inTrack: track mode: MyDocumentModifyAdd destinationPositions: nil];
        }
    }
    if (deltaNote != 0) {
        NSNumber *deltaNum = [NSNumber numberWithInt: deltaNote];
        for (i = 0; i < n; i++) {
            track = [self sortedTrackNumberAtIndex: i];
            if (track < 0)
                continue;
            pointSet = [document selectionOfTrack: track];
            if (pointSet == nil || MDPointSetGetCount([pointSet pointSet]) <= 0)
                continue;
            [document modifyCodes: deltaNum ofMultipleEventsAt: pointSet inTrack: track mode: MyDocumentModifyAdd];
        }
    }
}

- (void)dragDurationByTick: (MDTickType)deltaTick sender: (GraphicClientView *)sender
{
    int i, n, track;
    MDSelectionObject *pointSet;
    MyDocument *document = [self document];
    n = [self visibleTrackCount];
    if (deltaTick != 0) {
        NSNumber *deltaTickNum = [NSNumber numberWithLong: deltaTick];
        for (i = 0; i < n; i++) {
            track = [self sortedTrackNumberAtIndex: i];
            if (track < 0)
                continue;
            pointSet = [document selectionOfTrack: track];
            if (pointSet == nil || MDPointSetGetCount([pointSet pointSet]) <= 0)
                continue;
            [document modifyDurations: deltaTickNum ofMultipleEventsAt: pointSet inTrack: track mode: MyDocumentModifyAdd];
        }
    }
}

- (void)dragEventsOfKind: (int)kind andCode: (int)code byTick: (MDTickType)deltaTick andValue: (float)deltaValue sender: (GraphicClientView *)sender optionFlag: (BOOL)optionFlag
{
    int i, n, track;
    MDSelectionObject *pointSet;
    MyDocument *document = [self document];
    n = [self visibleTrackCount];
    if (deltaTick != 0) {
        NSNumber *deltaTickNum = [NSNumber numberWithLong: deltaTick];
        for (i = 0; i < n; i++) {
            track = [self sortedTrackNumberAtIndex: i];
            if (track < 0)
                continue;
            pointSet = [document selectionOfTrack: track];
            if (pointSet == nil || MDPointSetGetCount([pointSet pointSet]) <= 0)
                continue;
			if (optionFlag) {
				if ([document duplicateMultipleEventsAt: pointSet ofTrack: track selectInsertedEvents: YES])
					pointSet = [document selectionOfTrack: track];
			}				
            [document modifyTick: deltaTickNum ofMultipleEventsAt: pointSet inTrack: track mode: MyDocumentModifyAdd destinationPositions: nil];
        }
    }
    if (deltaValue != 0) {
        NSNumber *deltaNum = [NSNumber numberWithFloat: deltaValue];
        for (i = 0; i < n; i++) {
            track = [self sortedTrackNumberAtIndex: i];
            if (track < 0)
                continue;
            pointSet = [document selectionOfTrack: track];
            if (pointSet == nil || MDPointSetGetCount([pointSet pointSet]) <= 0)
                continue;
            [document modifyData: deltaNum forEventKind: kind ofMultipleEventsAt: pointSet inTrack: track mode: MyDocumentModifyAdd];
        }
    }
}

//- (IBAction)toggleDrawer: (id)sender
//{
//	if ([sender state] == NSOnState)
//		[myDrawer open];
//	else
//		[myDrawer close];
//}

- (IBAction)toolButton: (id)sender
{
	[sender setState: NSOnState];
	switch ([sender tag]) {
		case kIbeamButtonTag:
			[[[[self window] contentView] viewWithTag: kSelectButtonTag] setState: NSOffState];
			[[[[self window] contentView] viewWithTag: kPencilButtonTag] setState: NSOffState];
		//	[[[[self window] contentView] viewWithTag: kShapePopUpTag] setEnabled: NO];
		//	[[[[self window] contentView] viewWithTag: kModePopUpTag] setEnabled: NO];
			graphicTool = kGraphicSelectTool;
			graphicSelectionMode = kGraphicIbeamSelectionMode;
			break;
		case kSelectButtonTag:
			[[[[self window] contentView] viewWithTag: kIbeamButtonTag] setState: NSOffState];
			[[[[self window] contentView] viewWithTag: kPencilButtonTag] setState: NSOffState];
		//	[[[[self window] contentView] viewWithTag: kShapePopUpTag] setEnabled: NO];
		//	[[[[self window] contentView] viewWithTag: kModePopUpTag] setEnabled: NO];
			graphicTool = kGraphicSelectTool;
			graphicSelectionMode = kGraphicRectangleSelectionMode;
			break;
		case kPencilButtonTag:
			[[[[self window] contentView] viewWithTag: kIbeamButtonTag] setState: NSOffState];
			[[[[self window] contentView] viewWithTag: kSelectButtonTag] setState: NSOffState];
		//	[[[[self window] contentView] viewWithTag: kShapePopUpTag] setEnabled: YES];
		//	[[[[self window] contentView] viewWithTag: kModePopUpTag] setEnabled: YES];
			graphicTool = kGraphicPencilTool;
			break;
	}
}

- (IBAction)shapeSelected: (id)sender
{
	switch ([sender tag]) {
		case kLinearMenuTag:   graphicLineShape = kGraphicLinearShape; break;
		case kParabolaMenuTag: graphicLineShape = kGraphicParabolaShape; break;
		case kArcMenuTag:      graphicLineShape = kGraphicArcShape; break;
		case kSigmoidMenuTag:  graphicLineShape = kGraphicSigmoidShape; break;
		case kRandomMenuTag:   graphicLineShape = kGraphicRandomShape; break;
	}
}

- (IBAction)modeSelected: (id)sender
{
	switch ([sender tag]) {
		case kSetMenuTag:      graphicEditingMode = kGraphicSetMode; break;
		case kAddMenuTag:      graphicEditingMode = kGraphicAddMode; break;
		case kScaleMenuTag:    graphicEditingMode = kGraphicScaleMode; break;
		case kLimitMaxMenuTag: graphicEditingMode = kGraphicLimitMaxMode; break;
		case kLimitMinMenuTag: graphicEditingMode = kGraphicLimitMinMode; break;
	}
}

- (IBAction)quantizeSelected: (id)sender
{
	int i = [sender tag] - kQuantizeMenuTag;
	if (i <= 0) {
		quantize = 0;
	} else {
		int n, m;
		n = (i - 1) / 6;
		m = (i - 1) % 6;
		if (n == 1)
			quantize = 6.0;
		else if (n == 2)
			quantize = 8.0 / 3;
		else quantize = 4.0;
		while (m-- > 0)
			quantize *= 0.5;
	}
}

- (int)graphicTool
{
	return graphicTool;
}

- (int)graphicLineShape
{
	return graphicLineShape;
}

- (int)graphicEditingMode
{
	return graphicEditingMode;
}

- (int)graphicSelectionMode
{
	return graphicSelectionMode;
}

static BOOL
mouseMovedInView(NSView *view, NSEvent *theEvent)
{
    NSPoint pt;
    NSRect rect;
    if (view == nil)
        return NO;
    pt = [theEvent locationInWindow];
    rect = [view convertRect: [view visibleRect] toView: nil];
    if (NSMouseInRect(pt, rect, [view isFlipped])) {
        if ([view respondsToSelector: @selector(doMouseMoved:)])
            [(id)view doMouseMoved: theEvent];
        return YES;
    } else return NO;
}

- (void)mouseMoved: (NSEvent *)theEvent
{
    int i;
//    NSLog(@"GraphicWindowController.mouseMoved");
    for (i = 0; i < myClientViewsCount; i++) {
        if (mouseMovedInView(records[i].client, theEvent)) {
			[self mouseEvent:theEvent receivedByClientView:records[i].client];
			break;
		}
        if (mouseMovedInView(records[i].ruler, theEvent) || mouseMovedInView(records[i].splitter, theEvent))
            break;
    }
}

- (void)mouseEntered: (NSEvent *)theEvent
{
//	NSLog(@"mouseEntered");
}

- (void)mouseExited: (NSEvent *)theEvent
{
//	NSLog(@"mouseExited");
	[[NSCursor arrowCursor] set];
}

- (IBAction)editingRangeTextModified: (id)sender
{
	BOOL startFlag;
	long bar, beat, subtick;
	MDTickType tick, duration, endtick;
	const char *s;
	if ([sender tag] == kEditingRangeStartTextTag)
		startFlag = YES;
	else startFlag = NO;
	s = [[sender stringValue] UTF8String];
	if (s[0] == 0) {
		/*  Empty string: clear editing range  */
		tick = endtick = -1;
	} else {
		MDTickType tick1, tick2;
		if (MDEventParseTickString(s, &bar, &beat, &subtick) < 3)
			return;
		tick = MDCalibratorMeasureToTick(calib, bar, beat, subtick);
		duration = [[[self document] myMIDISequence] sequenceDuration];
		if (tick < 0)
			tick = 0;
		if (tick > duration)
			tick = duration;
		[[self document] getEditingRangeStart: &tick1 end: &tick2];
		if (startFlag) {
			if (tick >= tick2)
				endtick = tick;
			else endtick = tick2;
		} else {
			if (tick1 >= 0 && tick1 <= tick) {
				endtick = tick;
				tick = tick1;
			} else {
				endtick = tick;
			}
		}
	}
	[[self document] unselectAllEventsInAllTracks: self];
	[[self document] setEditingRangeStart: tick end: endtick];
}

- (IBAction)changeControlNumber:(id)sender
{
	[[NSApp delegate] performScriptCommand:@"change_control_number" forDocument:[self document]];
}

- (IBAction)shiftSelectedEvents:(id)sender
{
	[[NSApp delegate] performScriptCommand:@"shift_selected_events" forDocument:[self document]];
}

#pragma mark ==== Track list ====

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [[[self document] myMIDISequence] trackCount];
//	    return [self visibleTrackCount];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
row:(int)rowIndex
{
	id identifier = [aTableColumn identifier];
	int idnum = sTableColumnIDToInt(identifier);
//	int num = [self trackNumberAtIndex: rowIndex];
	switch (idnum) {
		case kTrackNumberID:
			if (rowIndex == 0)
				return @"C";
			else return [NSString localizedStringWithFormat:@"%d", rowIndex];
		case kTrackNameID:
			return [[[self document] myMIDISequence] trackName: rowIndex];
		case kChannelID: {
			int ch;
			if (rowIndex == 0)
				return nil;
			ch = [[[self document] myMIDISequence] trackChannel: rowIndex];
			if (ch >= 0)
				return [NSNumber numberWithInt: ch + 1];
			else return nil;
		}
		case kDeviceNameID:
			if (rowIndex == 0)
				return nil;
			else
				return [[[self document] myMIDISequence] deviceName: rowIndex];
		case kEditableID:
		case kVisibleID:
		case kSoloID:
		case kMuteID: {
			MDTrackAttribute attr;
			attr = [[[self document] myMIDISequence] trackAttributeAtIndex: rowIndex];
			if (idnum == kEditableID) {
				return (attr & kMDTrackAttributeEditable ? sPencilSmallImage : nil);
			} else if (idnum == kSoloID) {
			//	return (attr & kMDTrackAttributeMute ? nil : sSpeakerImage);
				return (attr & kMDTrackAttributeSolo ? sSoloImage : sSoloNonImage);
			} else if (idnum == kMuteID) {
				//	return (attr & kMDTrackAttributeMute ? nil : sSpeakerImage);
				if (attr & kMDTrackAttributeMute)
					return nil;
				else if (attr & kMDTrackAttributeMuteBySolo)
					return sSpeakerGrayImage;
				else return sSpeakerImage;
			} else if (idnum == kVisibleID) {
				return (attr & kMDTrackAttributeHidden ? sEyeCloseImage : sEyeOpenImage);
			} else return nil;
		}
	}
		
	return nil;
}

- (void)tableView:(NSTableView *)aTableView
setObjectValue:(id)anObject
forTableColumn:(NSTableColumn *)aTableColumn
row:(int)rowIndex
{
	int idnum = sTableColumnIDToInt([aTableColumn identifier]);
	MyDocument *doc = (MyDocument *)[self document];
	switch (idnum) {
		case kTrackNameID:
			[doc changeTrackName: anObject forTrack: rowIndex];
			break;
		case kChannelID: {
			int ch = [anObject intValue];
			if (ch >= 1 && ch <= 16)
				[doc changeTrackChannel: ch - 1 forTrack: rowIndex];
			break;
		}
		case kDeviceNameID:
			[doc changeDevice: anObject forTrack: rowIndex];
			break;
    }
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	MDTrackAttribute attr;
	int idnum = sTableColumnIDToInt([aTableColumn identifier]);
	if (idnum == kEditableID) {
		[aCell setRepresentedObject: [self colorForTrack: rowIndex enabled: YES]];		
		attr = [[[self document] myMIDISequence] trackAttributeAtIndex: rowIndex];
		[aCell setFillsColor:(attr & kMDTrackAttributeHidden) == 0];
	} else if (idnum == kSoloID) {
		attr = [[[self document] myMIDISequence] trackAttributeAtIndex: rowIndex];
		[aCell setFillsColor: (attr & kMDTrackAttributeSolo) != 0];
	} else if (idnum == kChannelID || idnum == kDeviceNameID) {
		if (rowIndex == 0)
			[aCell setEnabled: NO];
		else
			[aCell setEnabled: YES];
	}

/*		static NSImage *sEyeImage = nil;
		if (sEyeImage == nil)
			sEyeImage = [[NSImage imageNamed: @"eyes.png"] retain];
	//	[aCell setImage: ([aCell intValue] ? sEyeImage : nil)];
		[aCell setImage: (rowIndex % 2 == 0 ? sEyeImage : nil)];
	} else if (idnum == kEditableID) {
		static NSImage *sPencilImage = nil;
		if (sPencilImage == nil)
			sPencilImage = [[NSImage imageNamed: @"pencil_small.png"] retain];
	//	[aCell setImage: ([aCell intValue] ? sPencilImage : nil)];
		[aCell setImage: (rowIndex % 2 == 0 ? sPencilImage : nil)];
	} */
}

/*
- (IBAction)trackMenuItemSelected: (id)sender
{
	int tag = [sender tag];
	if (tag >= 0 && tag < [[[self document] myMIDISequence] trackCount])
		[self addTrack: tag];
	[myTableView reloadData];
	[self reloadClientViews];
}

- (IBAction)plusTrackButton: (id)sender
{
	[NSMenu popUpContextMenu: [self trackMenu] withEvent: [[self window] currentEvent] forView: sender];
}

- (IBAction)minusTrackButton: (id)sender
{
	NSMutableArray *array = [NSMutableArray array];
	NSEnumerator *en = [myTableView selectedRowEnumerator];
	id object;
	while ((object = [en nextObject]) != nil) {
		[array addObject: [NSNumber numberWithInt: [self trackNumberAtIndex: [object intValue]]]];
	}
//	NSLog(@"array = %@", array);
	[self removeTracksInArray: array];
	[myTableView deselectAll: self];
	[myTableView reloadData];
	[self reloadClientViews];
}
*/

/*
- (IBAction)tableClicked: (id)sender
{
	id column = [[sender tableColumns] objectAtIndex: [sender clickedColumn]];
	NSLog(@"tableClicked invoked");
	if ([@"color" isEqualToString: [column identifier]]) {
		int row = [sender clickedRow];
	//	long trackNum = [self trackNumberAtIndex: row];
	//	BOOL shiftFlag = (([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) != 0);
	//	if (![self isFocusTrack: trackNum]) {
	//		[self setFocusFlag: YES onTrack: trackNum extending: shiftFlag];
	//	} else if (shiftFlag) {
	//		[self setFocusFlag: NO onTrack: trackNum extending: YES];
	//	}
	//	[self setFocusFlag: ![self isFocusTrack: trackNum] onTrack: trackNum extending: YES];
		[myTableView reloadData];
		[self reloadClientViews];
	}
}
*/

- (void)trackTableAction:(id)sender
{
    int column, row;
    NSTableColumn *tableColumn;
//    NSCell *cell;
	MyDocument *doc = (MyDocument *)[self document];
	MyMIDISequence *seq = [doc myMIDISequence];
	MDTrackAttribute attr;
	int idnum;
	NSRect frame;
	BOOL editableTrackWasHidden = NO;
	BOOL shiftFlag = (([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) != 0);

    row = [myTableView clickedRow];
    column = [myTableView clickedColumn];

	if (column < 0)
		return;
    tableColumn = [[myTableView tableColumns] objectAtIndex: column];
	idnum = sTableColumnIDToInt([tableColumn identifier]);

	//  Check whether table header is clicked
	//  (lastMouseDownLocation is implemented in MyWindow)
	if (row < 0) {
		int attrMask, countChangedTrack;
		frame = [[myTableView headerView] headerRectOfColumn: column];
		if (!NSPointInRect([(MyWindow *)[self window] lastMouseDownLocation], [[myTableView headerView] convertRect: frame toView: nil]))
			return;
		switch (idnum) {
			//  Set the corresponding flag in all selected rows
			//  However, if the flag is already set for all rows, then unset the flag.
			case kEditableID:
				attrMask = kMDTrackAttributeEditable;
				break;
			case kSoloID:
				attrMask = kMDTrackAttributeSolo;
				break;
			case kMuteID:
				attrMask = kMDTrackAttributeMute;
				break;
			case kVisibleID:
				attrMask = kMDTrackAttributeHidden;
				break;
			default:
				return;
		}
		countChangedTrack = 0;
	//	seq = [[self document] myMIDISequence];
		for (row = [seq trackCount] - 1; row >= 0; row--) {
			if (![myTableView isRowSelected: row])
				continue;
			attr = [seq trackAttributeAtIndex: row];
			if (idnum == kEditableID && (attr & kMDTrackAttributeHidden))
				continue;
			if ((attr & attrMask) == 0) {
				attr |= attrMask;
				[seq setTrackAttribute: attr atIndex: row];
				countChangedTrack++;
			}
		}
		if (countChangedTrack == 0) {
			//  All flags are already set, so unset all of them
			for (row = [seq trackCount] - 1; row >= 0; row--) {
				if (![myTableView isRowSelected: row])
					continue;
				attr = [seq trackAttributeAtIndex: row];
				if (idnum == kEditableID && (attr & kMDTrackAttributeHidden))
					continue;
				attr &= ~attrMask;
				if (idnum == kVisibleID) {
					//  Hidden tracks are non-editable
					if (attr & kMDTrackAttributeEditable) {
						attr &= ~kMDTrackAttributeEditable;
						editableTrackWasHidden = YES;
					}
				}
				[seq setTrackAttribute: attr atIndex: row];
			}
		}
	} else {
		//  Check whether mouseUp occurred within the same cell as mouseDown
		frame = [myTableView frameOfCellAtColumn: column row: row];
		if (!NSPointInRect([(MyWindow *)[self window] lastMouseDownLocation], [myTableView convertRect: frame toView: nil]))
			return;
		switch (idnum) {
			case kEditableID: {
				attr = [seq trackAttributeAtIndex: row];
				if (attr & kMDTrackAttributeHidden)
					break;
				if (![self isFocusTrack: row]) {
					[self setFocusFlag: YES onTrack: row extending: shiftFlag];
				} else if (shiftFlag) {
					[self setFocusFlag: NO onTrack: row extending: YES];
				}
				break;
			}
			case kMuteID:
				[doc setMuteFlagOnTrack: row flag: -1];
				break;
			case kSoloID:
				[doc setSoloFlagOnTrack: row flag: -1];
				break;
			case kVisibleID:
				attr = [seq trackAttributeAtIndex: row];
				if (attr & kMDTrackAttributeHidden) {
					attr &= ~kMDTrackAttributeHidden;
				} else {
					attr |= kMDTrackAttributeHidden;
					if (attr & kMDTrackAttributeEditable) {
						//  Hidden tracks are non-editable
						attr &= ~kMDTrackAttributeEditable;
						editableTrackWasHidden = YES;
					}
				}
				[seq setTrackAttribute: attr atIndex: row];
				break;
			default:
				return;
		}
	}

	if (idnum == kVisibleID) {
		//  Check whether any editable track is left
		int firstVisibleRow = -1;
		for (row = [seq trackCount] - 1; row >= 0; row--) {
			attr = [seq trackAttributeAtIndex: row];
			if (attr & kMDTrackAttributeEditable) {
				firstVisibleRow = -2;
				break;
			}
			if (row > 0 && !(attr & kMDTrackAttributeHidden))
				firstVisibleRow = row;
		}
		if (firstVisibleRow > 0) {
			//  Make this row editable
			attr = [seq trackAttributeAtIndex: firstVisibleRow];
			attr |= kMDTrackAttributeEditable;
			[seq setTrackAttribute: attr atIndex: firstVisibleRow];
		}
	}

	if (idnum == kEditableID || idnum == kVisibleID)
		visibleTrackCount = -1;  // Invalidate the track list cache
		
	[myTableView reloadData];
	[self setNeedsReloadClientViews];
}

- (void)trackTableDoubleAction:(id)sender
{
    int column, row, idnum;
    NSTableColumn *tableColumn;

    row = [myTableView clickedRow];
    column = [myTableView clickedColumn];

	if (column < 0)
		return;
    tableColumn = [[myTableView tableColumns] objectAtIndex: column];
	idnum = sTableColumnIDToInt([tableColumn identifier]);
	if (idnum == kTrackNumberID) {
		[self openEventListWindow: sender];
		return;
	}
}

//- (float)timebase
//{
//	return [[self document] timebase];
//}

- (void)tableViewSelectionDidChange: (NSNotification *)aNotification
{
/*	if ([aNotification object] == myTableView) {
		NSButton *minusButton = (NSButton *)[[[self window] contentView] viewWithTag: kMinusButtonTag];
		if ([myTableView numberOfSelectedRows] > 0)
			[minusButton setEnabled: YES];
		else [minusButton setEnabled: NO];
	} */
	/*  Rebuild sortedTrackNumbers later  */
	visibleTrackCount = -1;
	[lastSelectedTracks release];
	lastSelectedTracks = [[NSIndexSet alloc] initWithIndexSet:[myTableView selectedRowIndexes]];
	[self setNeedsReloadClientViews];
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	int idnum = sTableColumnIDToInt([aTableColumn identifier]);
	if (idnum == kDeviceNameID) {
		/*  Rebuild the ComboBox item lists  */
		int i, n;
		id cell = [aTableColumn dataCell];
		[cell removeAllItems];
		[cell addItemWithObjectValue: @""];
		n = MDPlayerGetNumberOfDestinations();
		for (i = 0; i < n; i++) {
			char name[64];
			MDPlayerGetDestinationName(i, name, sizeof name);
			[cell addItemWithObjectValue: [NSString stringWithUTF8String: name]];
		}
	}
	return YES;
}

- (IBAction)openEventListWindow: (id)sender
{
	int index, n;
	NSMutableArray *array = [NSMutableArray array];
	n = [[[self document] myMIDISequence] trackCount];
	for (index = 0; index < n; index++) {
		if ([myTableView isRowSelected: index])
			[array addObject: [NSNumber numberWithInt: index]];
	}
    [(MyDocument *)[self document] createWindowForTracks: array ofType: gListWindowType];
//	[self openSelectedTracks: sender withClass: [ListWindowController class]];
}

- (IBAction)createNewTrack: (id)sender
{
	int index = [myTableView selectedRow];
	if (index < 0)
		index = [[[self document] myMIDISequence] trackCount];
	[(MyDocument *)[self document] insertTrack: nil atIndex: index];
}

- (IBAction)deleteSelectedTracks:(id)sender
{
	int index;
	for (index = [[[self document] myMIDISequence] trackCount] - 1; index > 0; index--) {
		if ([myTableView isRowSelected: index])
			[(MyDocument *)[self document] deleteTrackAt: index];
	}
/*    NSArray *array = [self selectedTracks];
    NSEnumerator *en;
    id object;
    en = [array reverseObjectEnumerator];
    while ((object = [en nextObject]) != nil) {
        long n = [object intValue];
        [(MyDocument *)[self document] deleteTrackAt: n];
    } */
}

- (IBAction)remapDevice: (id)sender
{
    RemapDevicePanelController *controller;
    NSMutableArray *selection;
    NSEnumerator *en;
    id obj;
    if ([myTableView numberOfSelectedRows] == 0)
        selection = nil;
    else {
        en = [myTableView selectedRowEnumerator];
        selection = [NSMutableArray array];
        while ((obj = [en nextObject]) != nil) {
            [selection addObject: obj];
        }
    }
    controller = [[RemapDevicePanelController allocWithZone: [self zone]] initWithDocument: [self document] trackSelection: selection];
    [controller beginSheetForWindow: [self window] invokeStopModalWhenDone: NO];
}

#pragma mark ====== Split view control ======

- (float)splitView: (NSSplitView *)sender constrainMaxCoordinate: (float)proposedMax ofSubviewAt: (int)offset
{
    return [sender bounds].size.width - 160.0;
}

- (float)splitView: (NSSplitView *)sender constrainMinCoordinate: (float)proposedMin ofSubviewAt: (int)offset
{
	return 100.0;
//    return proposedMin;
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return YES;
}

/*
- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
    NSView *theView = [myMainView superview];
    NSRect rect1 = [theView frame];
    NSView *theSuperOfScrollView = [myScroller superview];
    NSRect rect2 = [theSuperOfScrollView frame];
    rect2.origin.x = rect2.origin.x + rect2.size.width - rect1.size.width;
    rect2.size.width = rect1.size.width;
    [theSuperOfScrollView setFrame: rect2];
    [theSuperOfScrollView setNeedsDisplay: YES];
}
*/

#pragma mark ==== Responding to notification from other windows ====

- (void)trackModified: (NSNotification *)notification {
//	id trackObj = [[notification userInfo] objectForKey: @"track"];
//	if ([self containsTrack: [trackObj intValue]])
//		[self reloadClientViews];
//	[self updateMarkerList];
	visibleTrackCount = -1;
	[myTableView reloadData];
	[myPlayerView setNeedsDisplay: YES];
	[self setNeedsReloadClientViews];
//	[self editingRangeChanged: notification];
}

- (void)trackInserted: (NSNotification *)notification {
/*	int i;
	TrackInfo info;
	long track = [[[notification userInfo] objectForKey: @"track"] longValue];
	for (i = [trackInfo count] - 1; i >= 0; i--) {
		info = [self trackInfoAtIndex: i];
		if (info.trackNum >= track) {
			info.trackNum++;
			[self setTrackInfo: info atIndex: i];
		}
	}
	[sortedTrackNumbers release];
	sortedTrackNumbers = nil; */
	visibleTrackCount = -1;
	[myTableView reloadData];
	[myPlayerView setNeedsDisplay: YES];
	[self setNeedsReloadClientViews];
}

- (void)trackDeleted: (NSNotification *)notification {
/*	long track = [[[notification userInfo] objectForKey: @"track"] longValue];
	[self removeTrackAndFill: track]; */
	visibleTrackCount = -1;
	[myTableView reloadData];
	[myPlayerView setNeedsDisplay: YES];
	[self setNeedsReloadClientViews];
}

#pragma mark ==== Pasteboard support ====

- (int)countTracksToCopyWithSelectionList: (MDSelectionObject **)selArray rangeStart: (MDTickType *)outStartTick rangeEnd: (MDTickType *)outEndTick
{
	int i, numberOfSelectedTracks;
	MDSelectionObject *sel;
	MyDocument *doc = (MyDocument *)[self document];
	int numberOfTracks = [[doc myMIDISequence] trackCount];
	id firstResponder = [[self window] firstResponder];

	if (firstResponder == myMainView) {

		/*  Copy all selected events in editable tracks  */
		numberOfSelectedTracks = 0;
		for (i = 0; i < numberOfTracks; i++) {
			MDTrackAttribute attr = [[[self document] myMIDISequence] trackAttributeAtIndex: i];
			if ((attr & kMDTrackAttributeEditable) == 0)
				continue;
			sel = [doc selectionOfTrack: i];
			if (selArray != NULL)
				selArray[i] = sel;
			if (sel != nil)
				numberOfSelectedTracks++;
		}
		if (outStartTick != NULL && outEndTick != NULL)
			[doc getEditingRangeStart: outStartTick end: outEndTick];
		
		return numberOfSelectedTracks;

	} else if (firstResponder == myTableView) {

		/*  Copy all events in selected tracks  */
		numberOfSelectedTracks = 0;
		for (i = 0; i < numberOfTracks; i++) {
			if ([myTableView isRowSelected: i]) {
				if (selArray != NULL)
					selArray[i] = (MDSelectionObject *)(-1);
				numberOfSelectedTracks++;
			}
		}
		if (outStartTick != NULL)
			*outStartTick = kMDNegativeTick;
		if (outEndTick != NULL)
			*outEndTick = kMDMaxTick;
			
		return numberOfSelectedTracks;

	} else return 0;

}

- (void)doCopy: (BOOL)copyFlag andDelete: (BOOL)deleteFlag
{
	MDSelectionObject *sel, **selArray;
	MDTickType startTick, endTick;
	int i, numberOfSelectedTracks;
	MyDocument *doc = (MyDocument *)[self document];
	int numberOfTracks = [[doc myMIDISequence] trackCount];

	selArray = (MDSelectionObject **)calloc(sizeof(MDSelectionObject *), numberOfTracks);
	if (selArray == NULL)
		return;

	numberOfSelectedTracks = [self countTracksToCopyWithSelectionList: selArray rangeStart: &startTick rangeEnd: &endTick];
	if (numberOfSelectedTracks == 0)
		return;

	if (copyFlag)
		[doc copyWithSelections: selArray rangeStart: startTick rangeEnd: endTick];

	if (deleteFlag) {
		id firstResponder = [[self window] firstResponder];
		for (i = numberOfTracks - 1; i >= 0; i--) {
			if (selArray[i] == nil)
				continue;
			if (firstResponder == myMainView) {
				sel = [doc selectionOfTrack: i];
				[doc deleteMultipleEventsAt: sel fromTrack: i deletedEvents: NULL];
			} else if (firstResponder == myTableView) {
				[doc deleteTrackAt: i];
			}
		
		}
	}
	
	free(selArray);
}

- (void)doPasteWithMergeFlag: (BOOL)mergeFlag
{
//- (BOOL)getPasteboardSequence: (MDSequence **)outSequence catalog: (MDCatalog **)outCatalog;
	MyDocument *doc = (MyDocument *)[self document];
	MDSequence *seq;
	MDCatalog *catalog;
	int i, j, numberOfTracks, trackCount;
	int *trackList;
	id firstResponder;

	if (![doc getPasteboardSequence: &seq catalog: &catalog])
		return;
	trackCount = [[doc myMIDISequence] trackCount];
	numberOfTracks = MDSequenceGetNumberOfTracks(seq);
	trackList = (int *)calloc(sizeof(int), numberOfTracks);
	if (trackList == NULL)
		return;

	firstResponder = [[self window] firstResponder];

	if (firstResponder == myMainView) {

		/*  Look for the "editing" tracks  */
		for (i = j = 0; i < trackCount; i++) {
			MDTrackAttribute attr = [doc trackAttributeForTrack: i];
			if (attr & kMDTrackAttributeEditable) {
				trackList[j++] = i;
				if (j >= numberOfTracks)
					break;
			}
		}
		while (j < numberOfTracks) {
			trackList[j++] = i++;
		}
		
	} else if (firstResponder == myTableView) {
	
		/*  Look for the selected tracks  */
		for (i = j = 0; i < trackCount; i++) {
			if ([myTableView isRowSelected: i]) {
				trackList[j++] = i;
				if (j >= numberOfTracks)
					break;
			}
		}
		while (j < numberOfTracks) {
			trackList[j++] = i++;
		}
	
	} else return;
	
	i = [doc doPaste: seq toTracks: trackList rangeStart: catalog->startTick rangeEnd: catalog->endTick mergeFlag: mergeFlag];
	
	switch (i) {
		case 1:  /*  Trying to paste MIDI track to the conductor track  */
			NSRunCriticalAlertPanel(@"Cannot paste", @"You are trying to paste a MIDI track to the conductor track. Please unselect the conductor track in the track list.", @"OK", @"", @"");
			break;
	}

	free(catalog);
	MDSequenceRelease(seq);
	free(trackList);
}

- (IBAction)copy: (id)sender
{
	[self doCopy: YES andDelete: NO];
}

- (IBAction)cut: (id)sender
{
	[self doCopy: YES andDelete: YES];
}

- (IBAction)delete: (id)sender
{
	[self doCopy: NO andDelete: YES];
}

- (IBAction)paste: (id)sender
{
	[self doPasteWithMergeFlag: NO];
}

- (IBAction)merge: (id)sender
{
	[self doPasteWithMergeFlag: YES];
}

- (BOOL)validateUserInterfaceItem: (id)anItem
{
	id firstResponder;
	SEL sel = [anItem action];
	if (sel == @selector(copy:) || sel == @selector(cut:) || sel == @selector(delete:) || sel == @selector(shiftSelectedEvents:)) {
		if ([self countTracksToCopyWithSelectionList: NULL rangeStart: NULL rangeEnd: NULL] > 0)
			return YES;
		else return NO;
	} else if (sel == @selector(paste:)) {
		firstResponder = [[self window] firstResponder];
		if (firstResponder == myMainView || firstResponder == myTableView) {
			if ([[self document] isSequenceInPasteboard])
				return YES;
		}
		return NO;
	} else if (sel == @selector(openEventListWindow:) || sel == @selector(deleteSelectedTracks:)) {
		return [myTableView numberOfSelectedRows] > 0;
	} else if (sel == @selector(shiftSelectedEvents:)) {
		return [[self document] isSelectionEmptyInEditableTracks:YES] == NO;
	} else if ([self respondsToSelector:sel]) {
		return YES;
	} else return NO;
}

@end
