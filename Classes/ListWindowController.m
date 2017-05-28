//
//  ListWindowController.m
//
//  Created by Toshi Nagata.
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

#import "ListWindowController.h"
#import "NSWindowControllerAdditions.h"
#import "MyMIDISequence.h"
#import "MyTableHeaderView.h"
#import "MyTableView.h"
#import "MyDocument.h"
//#import "MyFieldEditor.h"
#import "MDObjects.h"
#import "EventFilterPanelController.h"
#import "MDRubyExtern.h"

@implementation ListWindowController

/*  イベント表示の色分け  */
static NSColor *sTextMetaColor = nil;
static NSColor *sMetaColor = nil;
static NSColor *sSysexColor = nil;
static NSColor *sProgramColor = nil;
static NSColor *sControlColor = nil;
static NSColor *sNoteColor = nil;
static NSColor *sKeyPresColor = nil;
static NSColor *sMiscColor = nil;

#pragma mark ====== NSWindowController(Addition) Overrides ======

- (id)init {
    self = [super initWithWindowNibName:@"ListWindow"];
	if (self) {
		[self setShouldCloseDocument: NO];
	}
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter]
        removeObserver:self];
	if (myPointer != NULL)
		MDPointerRelease(myPointer);
	if (myCalibrator != NULL)
		MDCalibratorRelease(myCalibrator);
/*	[myFieldEditor release]; */
    [super dealloc];
}

- (void)windowDidLoad {
	NSArray *array;
	int n;
	NSFont *font;
	NSTableColumn *column;
	NSTableHeaderView *headerView;
	MyTableHeaderView *myHeaderView;
	MDSequence *seq;

	[super windowDidLoad];

/*	myPointer = MDPointerNew(myTrack);
	MDPointerSetAutoAdjust(myPointer, 1);
	myCalibrator = MDCalibratorNew([[[self document] myMIDISequence] mySequence], myTrack, kMDEventTimeSignature, -1);
	MDCalibratorAppend(myCalibrator, myTrack, kMDEventTempo, -1);
	myRow = -1;
	myCount = -1;
	myTickColumnCount = 1;
	myTrackNumber = [[self myMIDISequence] lookUpTrack: myTrack];
	isLastRowSelected = NO; */

	myPlayingRow = -1;

	array = [myEventTrackView tableColumns];
	n = [array count];
	font = [NSFont userFixedPitchFontOfSize: -1.0];
	[myEventTrackView setRowHeight: [font defaultLineHeightForFont]];
	while (--n >= 0) {
		column = (NSTableColumn *)[array objectAtIndex: n];
		[[column dataCell] setFont: font];
	}
	headerView = [myEventTrackView headerView];
	myHeaderView = [[[MyTableHeaderView allocWithZone: [self zone]] initWithFrame:[headerView frame]] autorelease];
	[myEventTrackView setHeaderView:myHeaderView];
//	[myEventTrackView setDoubleAction: @selector(myDoubleAction:)];

	MDEventInit(&myDefaultEvent);
	MDSetKind(&myDefaultEvent, kMDEventNote);
	MDSetCode(&myDefaultEvent, 60);
	MDSetNoteOnVelocity(&myDefaultEvent, 64);
	MDSetNoteOffVelocity(&myDefaultEvent, 0);
	seq = [[[self document] myMIDISequence] mySequence];
	MDSetDuration(&myDefaultEvent, (seq == NULL ? 48 : MDSequenceGetTimebase(seq)));

	/*  Register the notification  */
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(updateEventTableView:)
		name:MyDocumentTrackModifiedNotification
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
		selector:@selector(documentSelectionDidChange:)
		name:MyDocumentSelectionDidChangeNotification
		object:[self document]];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(editingRangeChanged:)
		name:MyDocumentEditingRangeDidChangeNotification
		object:[self document]];

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(showPlayPosition:)
		name:MyDocumentPlayPositionNotification
		object:[self document]];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName {
	if (myTrack != NULL) {
		char buf[256];
		MDTrackGetName(myTrack, buf, sizeof buf);
	//	NSLog(@"Track name = %s\n", buf);
		if (buf[0] == 0) {
			snprintf(buf, sizeof buf, "(Track %ld)", myTrackNumber);
		}
		return [NSString stringWithFormat:@"%@:%s", displayName, buf];
	} else return displayName;
}

- (MyMIDISequence *)myMIDISequence {
    return [[self document] myMIDISequence];
}

- (BOOL)containsTrack: (int)index
{
    return (index == myTrackNumber);
}

- (void)addTrack: (int)index
{
	if (index < 0 || index >= [[self myMIDISequence] trackCount])
		return;
	myTrackNumber = index;
	myTrack = [[self myMIDISequence] getTrackAtIndex: index];
	if (myPointer != NULL)
		MDPointerRelease(myPointer);
	if (myCalibrator != NULL)
		MDCalibratorRelease(myCalibrator);
	myPointer = MDPointerNew(myTrack);
	MDPointerSetAutoAdjust(myPointer, 1);
	myCalibrator = MDCalibratorNew([[self myMIDISequence] mySequence], myTrack, kMDEventTimeSignature, -1);
	MDCalibratorAppend(myCalibrator, myTrack, kMDEventTempo, -1);
	myRow = -1;
	myCount = -1;
	myTickColumnCount = 1;
	isLastRowSelected = NO;
	[self updateEventTableView:nil];
}

- (BOOL)isFocusTrack: (int)trackNum
{
	return (trackNum == myTrackNumber);
}

#pragma mark ====== Notification handlers ======

- (void)trackInserted: (NSNotification *)notification
{
	myTrackNumber = [[self myMIDISequence] lookUpTrack: myTrack];
}

- (void)trackDeleted: (NSNotification *)notification
{
	myTrackNumber = [[self myMIDISequence] lookUpTrack: myTrack];
	if (myTrackNumber < 0) {
		//  This track is deleted
		[[self window] performClose: nil];
	}
}

- (void)documentSelectionDidChange: (NSNotification *)notification
{
    NSDictionary *info = [notification userInfo];
	id keys;
    if (selectionDidChangeNotificationLevel > 0)
        return;
	if ([myEventTrackView editedRow] >= 0)
		return;  //  Don't touch during TableView editing
	keys = [info objectForKey: @"keys"];
	if (keys != nil && [keys containsObject: [NSNumber numberWithInt: myTrackNumber]])
		[self reloadSelection];
}

- (void)updateEventTableView:(NSNotification *)notification
{
	if (notification == nil || [[[notification userInfo] objectForKey: @"track"] longValue] == myTrackNumber) {
		//  Reset myRow and myPointer
	//	MDPointerSetPosition(myPointer, -1);
	//	MDPointerForwardWithSelector(myPointer, EventSelector, myFilter);
	//	myRow = 0;
		myCount = -1;
		[myEventTrackView reloadData];
		
		//  Synchronize window title
		[self synchronizeWindowTitleWithDocumentName];
		
		[self updateInfoText];
		[self updateEditingRangeText];
	}
}

- (void)showPlayPosition:(NSNotification *)notification
{
	float beat = [[[notification userInfo] objectForKey: @"position"] floatValue];
	MDTickType tick = beat * [[self document] timebase];
	long n;
	int nearestRow, maxRow;

	/*  If event tracking in this window, then don't autoscroll to play position  */
	if ([[[NSRunLoop currentRunLoop] currentMode] isEqualToString:NSEventTrackingRunLoopMode] && [[NSApp currentEvent] window] == [self window])
		return;
	
	/*  Look for the event representing tick  */
	maxRow = [self numberOfRowsInTableView:myEventTrackView] - 1;
	if (tick < 0)
		nearestRow = -1;
	else {
		MDPointer *pt = MDPointerNew(myTrack);
		if (tick >= MDTrackGetDuration(myTrack))
			nearestRow = maxRow;
		else {
			if (MDPointerJumpToTick(pt, tick)) {
				n = MDPointerGetPosition(pt);
			} else {
				n = MDTrackGetNumberOfEvents(myTrack);
			}
			[self rowForEventPosition:n nearestRow:&nearestRow];
			if (nearestRow < 0)
				nearestRow = maxRow;
			else nearestRow--;
		}
		MDPointerRelease(pt);
	/*	NSLog(@"nearestRow = %d", (int)nearestRow); */
	}
	if (nearestRow >= 0) {
		NSRange visibleRowRange = [myEventTrackView rowsInRect:[myEventTrackView visibleRect]];
		if (!NSLocationInRange(nearestRow, visibleRowRange)) {
			n = nearestRow + visibleRowRange.length - 2;
			if (n >= maxRow)
				n = maxRow;
			[myEventTrackView scrollRowToVisible:n];
		}
	}
	[myEventTrackView setUnderlineRow:nearestRow];
	/*
	 if (nearestRow != myPlayingRow) {
		NSRect rowRect;
		if (nearestRow >= 0) {
			NSRange visibleRowRange = [myEventTrackView rowsInRect:[myEventTrackView visibleRect]];
			float y;
			if (!NSLocationInRange(nearestRow, visibleRowRange)) {
				n = nearestRow + visibleRowRange.length / 2;
				if (n >= maxRow)
					n = maxRow;
				[myEventTrackView scrollRowToVisible:n];
			}
			rowRect = [myEventTrackView rectOfRow:nearestRow];
			[myEventTrackView setNeedsDisplayInRect:rowRect];
			[myEventTrackView displayIfNeeded];
			[myEventTrackView lockFocus];
			y = rowRect.origin.y + 1;
			[NSBezierPath strokeLineFromPoint:NSMakePoint(rowRect.origin.x + 1, y) toPoint:NSMakePoint(rowRect.origin.x + rowRect.size.width - 1, y + rowRect.size.height - 2)];
			[myEventTrackView unlockFocus];
		}
		[myEventTrackView setNeedsDisplayInRect:[myEventTrackView rectOfRow:myPlayingRow]];
		myPlayingRow = nearestRow;
	 }
	*/
}

#pragma mark ====== NSTableView handling methods ======

static int
EventSelector(const MDEvent *ep, long position, void *inUserData)
{
	ListWindowFilterRecord *filter = (ListWindowFilterRecord *)inUserData;
	MDEventKind kind;
	int i;
	BOOL retval;
	if (filter == NULL)
		return 1;
	if (ep == NULL)
		return 0;
	kind = MDGetKind(ep);
	if (filter->mode == 0)
		return 1;
	if (kind == kMDEventNull)
		return 1;  /*  Always selected  */
	retval = (filter->mode == 1);
	for (i = 0; i < filter->count && filter->table[i].kind != kMDEventStop; i++) {
		if (kind == filter->table[i].kind) {
			if ((kind == kMDEventControl || kind == kMDEventMetaText || kind == kMDEventMetaMessage || kind == kMDEventMeta) && MDGetCode(ep) != filter->table[i].data)
				continue;
			return retval;
		}
	}
	return !retval;		
}

- (void)reloadSelection
{
    MDSelectionObject *obj = [[self document] selectionOfTrack: myTrackNumber];
    IntGroup *pset = [obj pointSet];
	NSMutableIndexSet *iset = [NSMutableIndexSet indexSet];
	long min = IntGroupMinimum(pset);
	long max = IntGroupMaximum(pset);
    selectionDidChangeNotificationLevel++;
	if (myTrack != NULL && myPointer != NULL) {
		MDPointerSetPosition(myPointer, -1);
		myRow = 0;
		while (MDPointerForwardWithSelector(myPointer, EventSelector, myFilter) != NULL) {
			long pos = MDPointerGetPosition(myPointer);
			if (pos >= min && IntGroupLookup(pset, pos, NULL))
				[iset addIndex: myRow];
			if (pos > max)
				break;
			myRow++;
		}
	}
	if (obj->isEndOfTrackSelected) {
		isLastRowSelected = YES;
		[iset addIndex: myCount];
	}
	[myEventTrackView selectRowIndexes: iset byExtendingSelection: NO];
    [myEventTrackView reloadData];
    selectionDidChangeNotificationLevel--;
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if (myTrack != NULL && myPointer != NULL) {
		if (myCount == -1) {
			/*  Count the number of events to display  */
			MDPointerSetPosition(myPointer, -1);
			myCount = 0;
			while (MDPointerForwardWithSelector(myPointer, EventSelector, myFilter) != NULL)
				myCount++;
			myRow = myCount;
			[myInfoText setStringValue:[NSString localizedStringWithFormat:@"%5ld events, %5ld shown",
				(long)MDTrackGetNumberOfEvents(myTrack), myCount]];
		}
		return myCount + 1;
	} else return 0;
}

- (MDEvent *)eventPointerForTableRow:(int)rowIndex
{
	long pos = [self eventPositionForTableRow: rowIndex];
	if (pos < 0)
		return NULL;
	if (rowIndex == myCount)
		return NULL;  /*  End of track  */
	return MDPointerCurrent(myPointer);
}

- (long)eventPositionForTableRow:(int)rowIndex
{
	if (myTrack == NULL || myPointer == NULL)
		return -1;
    if (myCount == -1)
        /*  Recalculate myCount  */
        [self numberOfRowsInTableView: myEventTrackView];
	if (rowIndex > myCount)
		return -1;
	if (rowIndex == myCount)
		return MDTrackGetNumberOfEvents(myTrack);  /* End-of-track */
	if (myRow > rowIndex) {
		while (myRow > rowIndex) {
			MDPointerBackwardWithSelector(myPointer, EventSelector, myFilter);
			myRow--;
		}
	} else if (myRow < rowIndex) {
		while (myRow < rowIndex) {
			MDPointerForwardWithSelector(myPointer, EventSelector, myFilter);
			myRow++;
		}
	}
	return MDPointerGetPosition(myPointer);
}

- (MDTickType)eventTickForTableRow:(int)rowIndex
{
	MDEvent *ep = [self eventPointerForTableRow: rowIndex];
	if (ep != NULL)
		return MDGetTick(ep);
	if (rowIndex == myCount)
		return MDTrackGetDuration(myTrack);
	else return kMDNegativeTick;
}

- (int)rowForEventPosition: (long)position nearestRow: (int *)nearestRow
{
    long mypos;
    if (myTrack == NULL || myPointer == NULL)
        return -1;
    if (myCount == -1)
        /*  Recalculate myCount  */
        [self numberOfRowsInTableView: myEventTrackView];
    if (position < 0) {
        if (nearestRow != NULL)
            *nearestRow = -1;
        return -1;
    } else if (position >= MDTrackGetNumberOfEvents(myTrack)) {
        if (nearestRow != NULL)
            *nearestRow = myCount;
        return -1;
    }
    mypos = MDPointerGetPosition(myPointer);
    if (mypos == position) {
        if (nearestRow != NULL)
            *nearestRow = myRow;
        return myRow;
    } else if (mypos > position) {
        do {
            myRow--;
        } while (MDPointerBackwardWithSelector(myPointer, EventSelector, myFilter) && (mypos = MDPointerGetPosition(myPointer)) > position);
        if (nearestRow != NULL)
            *nearestRow = myRow;
    } else {
        do {
            myRow++;
        } while (MDPointerForwardWithSelector(myPointer, EventSelector, myFilter) && (mypos = MDPointerGetPosition(myPointer)) < position);
        if (nearestRow != NULL)
            *nearestRow = (mypos == position ? myRow : myRow - 1);
    }
    if (mypos == position)
        return myRow;
    else return -1;
}

- (void)updateInfoText
{
	int n = MDTrackGetNumberOfEvents(myTrack) + 1;
	int m = [myEventTrackView numberOfSelectedRows];
	[myInfoText setStringValue:[NSString stringWithFormat:@"%d row%s/%d shown/%d selected", n, (n == 1 ? "" : "s"), myCount + 1, m]];
}

- (void)updateEditingRangeText
{
	MDTickType startTick, endTick;
	NSString *startString, *endString;
	[(MyDocument *)[self document] getEditingRangeStart: &startTick end: &endTick];
	if (startTick < 0 || startTick >= kMDMaxTick) {
		startString = endString = @"";
	} else {
		long startMeasure, startBeat, startSubTick;
		long endMeasure, endBeat, endSubTick;
		MDCalibratorTickToMeasure(myCalibrator, startTick, &startMeasure, &startBeat, &startSubTick);
		MDCalibratorTickToMeasure(myCalibrator, endTick, &endMeasure, &endBeat, &endSubTick);
		startString = [NSString stringWithFormat: @"%4ld:%2ld:%4ld", startMeasure, startBeat, startSubTick];
		endString = [NSString stringWithFormat: @"%4ld:%2ld:%4ld", endMeasure, endBeat, endSubTick];
	}
	
	[startEditingRangeText setStringValue: startString];
	[endEditingRangeText setStringValue: endString];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
row:(int)rowIndex
{
	id identifier = [aTableColumn identifier];
	MDEvent *ep;
	MDTickType tick;
	MDTimeType time;
	long bar, beat, count;
	
	if (rowIndex == myCount) {
		/*  The "end of track" row  */
		ep = NULL;
		tick = MDTrackGetDuration(myTrack);
	} else {
		ep = [self eventPointerForTableRow:rowIndex];
		if (ep == NULL)
			return nil;
		tick = MDGetTick(ep);
	}
	
    if ([@"bar" isEqualToString: identifier]) {
		MDCalibratorTickToMeasure(myCalibrator, tick, &bar, &beat, &count);
		return [NSString localizedStringWithFormat:@"%4d:%2d:%4d", (int)bar, (int)beat, (int)count];
	} else if ([@"sec" isEqualToString: identifier]) {
		time = MDCalibratorTickToTime(myCalibrator, tick);
		return [NSString localizedStringWithFormat:@"%8.3f", (double)(time / 1000000.0)];
	} else if ([@"msec" isEqualToString: identifier]) {
		time = MDCalibratorTickToTime(myCalibrator, tick);
		return [NSString localizedStringWithFormat:@"%8.2f", (double)(time / 1000.0)];
	} else if ([@"count" isEqualToString: identifier]) {
		return [NSString localizedStringWithFormat:@"%8ld", (long)tick];
	} else if ([@"deltacount" isEqualToString: identifier]) {
		if (rowIndex == myCount) {
			ep = [self eventPointerForTableRow:rowIndex - 1];
			if (ep != NULL)
				tick -= MDGetTick(ep);
		} else if (rowIndex > 0) {
			ep = MDPointerBackward(myPointer);
			MDPointerForward(myPointer);
			if (ep != NULL)
				tick -= MDGetTick(ep);
		}
		return [NSString localizedStringWithFormat:@"%6ld", (long)tick];
	} else if ([@"st" isEqualToString: identifier]) {
		ep = MDPointerForward(myPointer);
		MDPointerBackward(myPointer);
		if (ep == NULL)
			tick = 0;
		else tick = MDGetTick(ep) - tick;
		return [NSString localizedStringWithFormat:@"%6ld", (long)tick];
    }
	if ([@"ch" isEqualToString: identifier]) {
		if (ep != NULL && MDIsChannelEvent(ep))
			return [NSString localizedStringWithFormat:@"%d", (int)MDGetChannel(ep)];
		else return nil;
    } else {
		char eventStr[2048];
		if ([@"event" isEqualToString: identifier]) {
			if (ep == NULL)
				return @"--End--";
			else
				MDEventToKindString(ep, eventStr, sizeof(eventStr));
		} else if (ep != NULL) {
			if ([@"duration" isEqualToString: identifier]) {
				MDEventToGTString(ep, eventStr, sizeof(eventStr));
			} else if ([@"data" isEqualToString: identifier]) {
				MDEventToDataString(ep, eventStr, sizeof(eventStr));
			} else return nil;
		} else return nil;
		return [NSString stringWithUTF8String:eventStr];
	}
	return nil;
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	id identifier = [aTableColumn identifier];
	MDEvent *ep;
	NSColor *color;

    if ([@"bar" isEqualToString: identifier]
	||  [@"sec" isEqualToString: identifier]
	||  [@"msec" isEqualToString: identifier]
	||  [@"count" isEqualToString: identifier]
	||  [@"ch" isEqualToString: identifier])
		return;

	/*  Set color according to the event kind  */
	/*  Note: use black color if the row is selected (for better visibility)  */
	if ([aTableView isRowSelected: rowIndex]) {
		[aCell setTextColor: [NSColor blackColor]];
		return;
	}

	ep = [self eventPointerForTableRow:rowIndex];
	if (ep == NULL || MDIsTextMetaEvent(ep)) {
		if (sTextMetaColor == nil)
			sTextMetaColor = [[NSColor colorWithDeviceRed: 0.5 green: 0.0 blue: 0.5 alpha: 1.0] retain];
		color = sTextMetaColor;
	} else if (MDIsMetaEvent(ep)) {
		if (sMetaColor == nil)
			sMetaColor = [[NSColor colorWithDeviceRed: 0.0 green: 0.5 blue: 0.2 alpha: 1.0] retain];
		color = sMetaColor;
	} else if (MDIsSysexEvent(ep)) {
		if (sSysexColor == nil)
			sSysexColor = [[NSColor colorWithDeviceRed: 0.5 green: 0.5 blue: 0.0 alpha: 1.0] retain];
		color = sSysexColor;
	} else {
		switch (MDGetKind(ep)) {
			case kMDEventProgram:
				if (sProgramColor == nil)
					sProgramColor = [[NSColor colorWithDeviceRed: 0.0 green: 0.0 blue: 1.0 alpha: 1.0] retain];
				color = sProgramColor;
				break;
			case kMDEventControl:
		/*	case kMDEventRPNControl:
			case kMDEventRPNFine:
			case kMDEventRPNInc: */
				if (sControlColor == nil)
					sControlColor = [[NSColor colorWithDeviceRed: 0.0 green: 0.5 blue: 0.0 alpha: 1.0] retain];
				color = sControlColor;
				break;
			case kMDEventNote:
				if (sNoteColor == nil)
					sNoteColor = [[NSColor blackColor] retain];
				color = sNoteColor;
				break;
			case kMDEventKeyPres:
			case kMDEventChanPres:
				if (sKeyPresColor == nil)
					sKeyPresColor = [[NSColor colorWithDeviceRed: 0.5 green: 0.2 blue: 0.0 alpha: 1.0] retain];
				color = sKeyPresColor;
				break;
			default:
				if (sMiscColor == nil)
					sMiscColor = [[NSColor colorWithDeviceRed: 0.5 green: 0.0 blue: 0.0 alpha: 1.0] retain];
				color = sMiscColor;
				break;
		}
	}
	[aCell setTextColor: color];
}

static void
newEventFromKindAndCode(MDEvent *ep, MDEventFieldData ed)
{
	MDEventDefault(ep, ed.ucValue[0]);
	MDSetCode(ep, ed.ucValue[1]);
}

- (void)tableView:(NSTableView *)aTableView
setObjectValue:(id)anObject
forTableColumn:(NSTableColumn *)aTableColumn
row:(int)rowIndex
{
	id identifier = [aTableColumn identifier];
	const char *descStr = [[anObject description] UTF8String];
	MDEvent *ep;
	MDTickType tick;
	MDTimeType time;
	MyDocument *document;
	long trackNo, position;
	char buf[2048];
	BOOL mod = NO;
	
	strncpy(buf, [[anObject description] UTF8String], sizeof buf - 1);
	buf[sizeof buf - 1] = 0;
	
	/*  Prepare arguments for posting action  */
	trackNo = myTrackNumber; /* [[self myMIDISequence] lookUpTrack: [self MIDITrack]]; */
	position = [self eventPositionForTableRow:rowIndex];
	document = (MyDocument *)[self document];

	tick = kMDNegativeTick;
    if ([@"bar" isEqualToString: identifier]) {
		long bar, beat, count;
		if (MDEventParseTickString(buf, &bar, &beat, &count) < 3)
			return;
		tick = MDCalibratorMeasureToTick(myCalibrator, bar, beat, count);
	} else if ([@"sec" isEqualToString: identifier]) {
		time = atof(buf) * 1000000.0;
		tick = MDCalibratorTimeToTick(myCalibrator, time);
	} else if ([@"msec" isEqualToString: identifier]) {
		time = atof(buf) * 1000.0;
		tick = MDCalibratorTimeToTick(myCalibrator, time);
	} else if ([@"count" isEqualToString: identifier]) {
		tick = atol(buf);
	} else if ([@"deltacount" isEqualToString: identifier]) {
		tick = atol(buf);
		if (rowIndex > 0) {
			ep = [self eventPointerForTableRow:rowIndex - 1];
			if (ep != NULL)
				tick += MDGetTick(ep);
		}
	}
	
	ep = [self eventPointerForTableRow:rowIndex];
	if (tick != kMDNegativeTick) {
		/*  set tick  */
		long npos;
		if (rowIndex == myCount) {
			/*  Change track duration  */
			if ([document changeTrackDuration: tick ofTrack: trackNo]) {
				[[document undoManager] setActionName:NSLocalizedString(
					@"Change Track Duration", @"Name of undo/redo menu item after the track duration is explicitly changed")];
			}
		} else {
			npos = [document changeTick: tick atPosition: position inTrack: trackNo originalPosition: -1];
			if (npos >= 0) {
				/*  Select npos'th event and show it  */
				[myEventTrackView selectRow: npos byExtendingSelection: NO];
				[[document undoManager] setActionName:NSLocalizedString(
					@"Change Tick", @"Name of undo/redo menu item after a single tick value is changed")];
			}
		}

	} else {
	
		/*  If ep == NULL, then edit of elements other than tick is impossible  */
		if (ep == NULL)
			return;
			
		if ([@"st" isEqualToString: identifier]) {

			tick = atol(buf);
			/*  set ST  */

		} else if ([@"ch" isEqualToString: identifier]) {

			int ch;
			ch = atoi(buf);
			/*  set channel  */

		} else {
			MDEventFieldCode code;
			MDEventFieldData ed;
			ed.whole = 0;
			if ([@"event" isEqualToString: identifier]) {
				code = MDEventKindStringToEvent(buf, &ed);
				if (code == kMDEventFieldKindAndCode) {
					if (ed.ucValue[0] == MDGetKind(ep)
					|| (ed.ucValue[0] == kMDEventNote && (MDGetKind(ep) == kMDEventNote))) {
						mod = [document changeValue: ed.whole ofType: code atPosition: position inTrack: trackNo];
					} else {
						MDEventObject *newEvent = [[[MDEventObject allocWithZone: [self zone]] init] autorelease];
						newEventFromKindAndCode(&newEvent->event, ed);
						MDSetTick(&newEvent->event, MDGetTick(ep));
						newEvent->position = position;
						if ((myTrackNumber == 0 && MDEventIsEventAllowableInConductorTrack(&newEvent->event))
						|| (myTrackNumber != 0 && MDEventIsEventAllowableInNonConductorTrack(&newEvent->event))) {
							mod = [document replaceEvent: newEvent inTrack: trackNo];
						} else {
							[[NSAlert alertWithMessageText: @"Bad Event Type" defaultButton: nil alternateButton: nil otherButton: nil informativeTextWithFormat: @"This event type cannot be placed in a %s track.", (myTrackNumber == 0 ? "conductor" : "non-conductor")] runModal];
						}
					}
				}
			} else if ([@"duration" isEqualToString: identifier]) {
				/* code = MDEventGTStringToEvent(ep, buf, &ed); */
				if (MDGetKind(ep) == kMDEventNote) {
					/*  Change the tick of the note off  */
					tick = atol(buf);
					mod = [document changeDuration: tick atPosition: position inTrack: trackNo];
				}
			} else if ([@"data" isEqualToString: identifier]) {
				NSData *data = nil;  //  Will be used for kMDEventFieldBinaryData
				code = MDEventDataStringToEvent(ep, buf, &ed);
				if (code == kMDEventFieldInvalid) {
					char *msg;
					asprintf(&msg, "%.*s<?>%s", (int)ed.longValue, buf, buf + ed.longValue);
					[[NSAlert alertWithMessageText: @"Bad Event Data" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"The data string cannot be converted to an event data: %s", msg] runModal];
					free(msg);
				} else if (code == kMDEventFieldBinaryData) {
					if (data == nil) {
						if (ed.binaryData != NULL)
							data = [NSData dataWithBytes: ed.binaryData + sizeof(long) length: *((long *)ed.binaryData)];
					}
					mod = [document changeMessage: data atPosition: position inTrack: trackNo];
					if (ed.binaryData != NULL) {
						free(ed.binaryData);
						ed.binaryData = NULL;
					}
				} else {
					mod = [document changeValue: ed.whole ofType: code atPosition: position inTrack: trackNo];
				}
			} else return;	/*  No action  */
			
			if (mod) {
				const MDEvent *cep = [document eventAtPosition: position inTrack: trackNo];
				MDEventClear(&myDefaultEvent);  /*  Release the message if present  */
				MDEventCopy(&myDefaultEvent, cep, 1);
				[[document undoManager] setActionName: NSLocalizedString(
					@"Modify Event", @"Name of undo/redo menu item after event is modified")];
			}
		}
	}
	
	//  Update other windows before going forward
	[[self document] postTrackModifiedNotification: nil];
}

//- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(int)rowIndex
//{
//    if (rowIndex == myCount)
//        return allowSelectingLastRow;
//    else return YES;
//}

//- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
//{
//	NSLog(@"selectionShouldChangeInTableView invoked");
//	return YES;
//}
/*
- (BOOL)selectionShouldChangeInTableView: (NSTableView *)aTableView
{
	id firstResponder = [[self window] firstResponder];
	if ([firstResponder isKindOfClass: [NSText class]] && [[firstResponder delegate] isKindOfClass: [MyTableView class]]) {
		if ([[self window] makeFirstResponder: aTableView]) {
			[[self window] endEditingFor: nil];
			return YES;
		} else {
			NSBeep();
			return NO;
		}
	}
	return YES;
}
*/
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    MDSelectionObject *pointSet;
    NSEnumerator *enumerator;
    id obj;
    MDStatus sts;
    int numberOfRows, theRow;
	unsigned flags;
    if (selectionDidChangeNotificationLevel > 0)
        return;

    selectionDidChangeNotificationLevel++;
	
	/*  Check whether shift or command key is pressed  */
	flags = [[[self window] currentEvent] modifierFlags];
	if (!(flags & (NSCommandKeyMask | NSShiftKeyMask))) {
		/*  If not, then unselect all events  */
		[(MyDocument *)[self document] unselectAllEventsInAllTracks: self];
	}
	
    pointSet = [[MDSelectionObject allocWithZone: [self zone]] init];
    enumerator = [myEventTrackView selectedRowEnumerator];
    numberOfRows = [self numberOfRowsInTableView: myEventTrackView];
	isLastRowSelected = NO;
    while ((obj = [enumerator nextObject]) != nil) {
        theRow = [obj intValue];
        if (theRow == numberOfRows - 1) {
			pointSet->isEndOfTrackSelected = YES;
			isLastRowSelected = YES;
            continue;
		}
        sts = IntGroupAdd(pointSet->pointSet, [self eventPositionForTableRow: theRow], 1);
        if (sts != kMDNoError)
            break;
    }
    [(MyDocument *)[self document] setSelection: pointSet inTrack: myTrackNumber sender: self];
    [pointSet release];
    selectionDidChangeNotificationLevel--;
	[self updateInfoText];
}

//  EventKindTextFieldCell informal protocol
- (id)willUseMenu: (id)menu forEvent: (NSEvent *)anEvent inRow: (int)row
{
	if (row == myCount)
		return nil;
	else return menu;
}

//  MyTableView delegate method
- (BOOL)myTableView:(MyTableView *)tableView shouldEditColumn:(int)column row:(int)row
{
	if (tableView == myEventTrackView) {
		MDEvent *ep = [self eventPointerForTableRow:row];
		int count = [self eventPositionForTableRow:row];
		if (ep == NULL)
			return NO;
	/*	if (MDGetKind(ep) == kMDEventSysex) {
			//  Special editing feature
			int n = Ruby_callMethodOfDocument("edit_sysex_dialog", [self document], 0, "ii", (int)myTrackNumber, count);
			if (n != 0)
				Ruby_showError(n);
			return NO;
		} */
	}
	return YES;
}

//  NSControl delegate method; check if the edited text is valid
- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor
{
	if (control == myEventTrackView) {
		id identifier;
		int col = [myEventTrackView editedColumn];
		int row = [myEventTrackView editedRow];
		if (col < 0)
			return NO;
		identifier = [[[myEventTrackView tableColumns] objectAtIndex: col] identifier];
		if ([@"event" isEqualToString: identifier]) {
			MDEventFieldCode code;
			MDEventFieldData ed;
			ed.whole = 0;
			code = MDEventKindStringToEvent([[fieldEditor string] UTF8String], &ed);
			if (code == kMDEventFieldKindAndCode) {
				MDEvent event;
				long position;
				MDEventInit(&event);
				newEventFromKindAndCode(&event, ed);
				position = [self eventPositionForTableRow: row];
				if (!EventSelector(&event, position, myFilter)) {
					if (NSRunAlertPanel(@"Alert", @"This event will be hidden and disappear from this window.", @"OK", @"Change Event", nil) == NSAlertAlternateReturn)
						return NO;
				}
				return YES;
			}
		}
	}
	return YES;
}

#pragma mark ====== PopUp button handlers ======

- (IBAction)myAppendColumn:(id)sender
{
}

- (IBAction)myRemoveColumn:(id)sender
{
}

- (IBAction)myShowSecond:(id)sender
{
	[myClickedColumn setIdentifier:@"sec"];
	[[myClickedColumn headerCell] setStringValue:@"Seconds"];
	[myEventTrackView reloadData];
}

- (IBAction)myShowMillisecond:(id)sender
{
	[myClickedColumn setIdentifier:@"msec"];
	[[myClickedColumn headerCell] setStringValue:@"Milliseconds"];
//	[[myClickedColumn headerCell] setAlignment:NSCenterTextAlignment];
	[myEventTrackView reloadData];
}

- (IBAction)myShowBarBeatCount:(id)sender
{
	[myClickedColumn setIdentifier:@"bar"];
	[[myClickedColumn headerCell] setStringValue:@"Bar: beat: count"];
//	[[myClickedColumn headerCell] setAlignment:NSCenterTextAlignment];
	[myEventTrackView reloadData];
}

- (IBAction)myShowCount:(id)sender
{
	[myClickedColumn setIdentifier:@"count"];
	[[myClickedColumn headerCell] setStringValue:@"Count"];
//	[[myClickedColumn headerCell] setAlignment:NSCenterTextAlignment];
	[myEventTrackView reloadData];
}

- (IBAction)myShowDeltaCount: (id)sender
{
	[myClickedColumn setIdentifier:@"deltacount"];
	[[myClickedColumn headerCell] setStringValue:@"delta count"];
	[myEventTrackView reloadData];
}

- (IBAction)eventKindMenuSelected:(id)sender
{
	int tag, rowIndex;
	long trackNo, position;
	MyDocument *document;
	MDEvent *ep;
	MDEventObject *newEvent;
	MDEventFieldData ed;
	BOOL mod = NO;

	trackNo = myTrackNumber; /* [[self myMIDISequence] lookUpTrack: [self MIDITrack]]; */
	rowIndex = [myEventTrackView selectedRow];
	position = [self eventPositionForTableRow: rowIndex];
	document = (MyDocument *)[self document];
	ep = [self eventPointerForTableRow:rowIndex];
	newEvent = [[[MDEventObject allocWithZone: [self zone]] init] autorelease];
	tag = [sender tag];	
	if (tag < 1000) {
		switch (tag) {
			case 0: /* Note */
				ed.ucValue[0] = kMDEventNote;
				ed.ucValue[1] = 60;
				break;
			case 1: /* Control (non-specific) */
				ed.ucValue[0] = kMDEventControl;
				ed.ucValue[1] = 0;
				break;
			case 2: /* Pitch bend */
				ed.ucValue[0] = kMDEventPitchBend;
				break;
			case 3: /* Program change */
				ed.ucValue[0] = kMDEventProgram;
				break;
			case 4: /* Channel pressure */
				ed.ucValue[0] = kMDEventChanPres;
				break;
			case 5: /* Polyphonic key pressure */
				ed.ucValue[0] = kMDEventKeyPres;
				ed.ucValue[1] = 60;
				break;
			case 6: /* Meta event (non-specific) */
				ed.ucValue[0] = kMDEventMetaText;
				ed.ucValue[1] = kMDMetaText;
				break;
			case 7: /* System exclusive */
				ed.ucValue[0] = kMDEventSysex;
				break;
			default:
				return;
		}
	} else if (tag >= 1000 && tag < 2000) {
		/*  Control events  */
		ed.ucValue[0] = kMDEventControl;
		ed.ucValue[1] = (tag - 1000) & 127;
	} else if (tag >= 2000 && tag < 3000) {
		/*  Meta events  */
		switch (tag) {
			case 2000: /* tempo */
				ed.ucValue[0] = kMDEventTempo;
				break;
			case 2001: /* meter */
				ed.ucValue[0]= kMDEventTimeSignature;
				break;
			case 2002: /* key */
				ed.ucValue[0] = kMDEventKey;
				break;
			case 2003: /* smpte */
				ed.ucValue[0] = kMDEventSMPTE;
				break;
			case 2004: /* port */
				ed.ucValue[0] = kMDEventPortNumber;
				break;
			case 2005: /* copyright */
			case 2006: /* sequence */
			case 2007: /* instrument */
			case 2008: /* lyric */
			case 2009: /* marker */
			case 2010: /* cue */
			case 2011: /* program */
			case 2012: /* device */
				ed.ucValue[0] = kMDEventMetaText;
				ed.ucValue[1] = tag - 2005 + kMDMetaCopyright;
				break;
			default:
				return;
		}
	}

	/*  Replace the event with the new event  */
	newEventFromKindAndCode(&newEvent->event, ed);
	MDSetTick(&newEvent->event, MDGetTick(ep));
	newEvent->position = position;
	mod = [document replaceEvent: newEvent inTrack: trackNo];
	if (mod) {
		const MDEvent *cep = [document eventAtPosition: position inTrack: trackNo];
		MDEventClear(&myDefaultEvent);  /*  Release the message if present  */
		MDEventCopy(&myDefaultEvent, cep, 1);
		[[document undoManager] setActionName: NSLocalizedString(
			@"Modify Event", @"Name of undo/redo menu item after event is modified")];
	}
}

- (NSMenu *)tableHeaderView:(NSTableHeaderView *)headerView popUpMenuAtHeaderColumn:(int)column
{
	NSTableColumn *tableColumn;
	NSString *identifier;
	int i, tag;
//	NSLog(@"Popup menu for column %d\n", column);
	tableColumn = (NSTableColumn *)[[myEventTrackView tableColumns] objectAtIndex:column];
	identifier = (NSString *)[tableColumn identifier];
    if ([@"bar" isEqualToString: identifier]) {
		tag = 0;
	} else if ([@"sec" isEqualToString: identifier]) {
		tag = 1;
	} else if ([@"msec" isEqualToString: identifier]) {
		tag = 2;
	} else if ([@"count" isEqualToString: identifier]) {
		tag = 3;
	} else if ([@"deltacount" isEqualToString: identifier]) {
		tag = 4;
	} else return nil;
	for (i = 0; i < 4; i++) {
		[[myTickDescriptionMenu itemWithTag:i] setState:(i == tag ? NSOnState : NSOffState)];
	}
	myClickedColumn = tableColumn;
	return myTickDescriptionMenu;
}

#pragma mark ====== Editing ======

- (IBAction)deleteSelectedEvents: (id)sender
{
	NSEnumerator *en = [myEventTrackView selectedRowEnumerator];
	IntGroupObject *pointSet = [[[IntGroupObject allocWithZone: [self zone]] init] autorelease];
	MDStatus sts;
	BOOL mod;
	id obj;
	int n, eot;
	eot = [myEventTrackView numberOfRows] - 1;	//  End Of Track
	while ((obj = [en nextObject]) != nil) {
		n = [obj intValue];
		if (n == eot)
			continue;
		sts = IntGroupAdd(pointSet->pointSet, [self eventPositionForTableRow: n], 1);
		if (sts != kMDNoError)
			return;		//  Cannot proceed
	}
	mod = [(MyDocument *)[self document]
			deleteMultipleEventsAt: (IntGroupObject *)pointSet
		   fromTrack: myTrackNumber deletedEvents: NULL];
	if (mod) {
		[[[self document] undoManager] setActionName:NSLocalizedString(
			@"Delete Selection", @"Name of undo/redo menu item after event is modified")];
	}
	myCount = -1;
	[myEventTrackView reloadData];
}

- (void)startEditAtColumn: (int)column row: (int)row
{
	[myEventTrackView selectRow: row byExtendingSelection: NO];
	if (column < 0)
	//	column = [myEventTrackView columnWithIdentifier: @"event"];
		column = 0;
	[myEventTrackView editColumn: column row: row withEvent: nil select: YES];
}

- (void)startEditAtColumn: (int)column creatingEventWithTick: (MDTickType)tick atPosition: (long)position
{
	MDEvent *ep;
	MDPointer *ptr = MDPointerNew(myTrack);
	MDEventObject *newEvent;
//	long num = MDTrackGetNumberOfEvents(myTrack);
	int nearestRow, row;
	if (!EventSelector(&myDefaultEvent, position, myFilter))
		/*  The default event will not be displayed: clear the default event  */
		MDEventClear(&myDefaultEvent);
	if (myTrackNumber == 0 && !MDEventIsEventAllowableInConductorTrack(&myDefaultEvent)) {
		MDEventClear(&myDefaultEvent);
		MDSetKind(&myDefaultEvent, kMDEventTempo);
		MDSetTempo(&myDefaultEvent, 120.0);
	} else if (myTrackNumber != 0 && !MDEventIsEventAllowableInNonConductorTrack(&myDefaultEvent)) {
		MDEventClear(&myDefaultEvent);
		MDSetKind(&myDefaultEvent, kMDEventNote);
		MDSetCode(&myDefaultEvent, 60);
		MDSetNoteOnVelocity(&myDefaultEvent, 64);
		MDSetNoteOffVelocity(&myDefaultEvent, 0);
		MDSetDuration(&myDefaultEvent, [[self document] timebase]);
	}

	newEvent = [[[MDEventObject allocWithZone: [self zone]] initWithMDEvent: &myDefaultEvent] autorelease];
	if (tick < 0) {
		/*  If tick is not specified, then the tick at (position-1) is used  */
		tick = 0;
		if (position >= 0) {
			MDPointerSetPosition(ptr, position - 1);
			if ((ep = MDPointerCurrent(ptr)) != NULL)
				tick = MDGetTick(ep);
		}
	}
	if (position < 0) {
		/*  If position is not specified, then the last position before tick is used  */
		position = 0;
		if (tick >= 0) {
			MDPointerJumpToTick(ptr, tick + 1);
			position = MDPointerGetPosition(ptr);
			if (position < 0)
				position = 0;
		}
	}
	newEvent->position = position;
	MDSetTick(&newEvent->event, tick);
	[(MyDocument *)[self document]
		insertEvent: newEvent
		toTrack: myTrackNumber];
	myCount = -1;
	[myEventTrackView reloadData];
	
	//  Update other windows before going forward
	[[self document] postTrackModifiedNotification: nil];
	
	row = [self rowForEventPosition: position nearestRow: &nearestRow];
	[self startEditAtColumn: column row: row];
}

- (IBAction)insertNewEvent: (id)sender
{
	MDTickType tick, endTick;
	long position;
	MDEvent *ep;
	int row = [myEventTrackView selectedRow];
	if (row < 0) {
		position = -1;
		[(MyDocument *)[self document] getEditingRangeStart: &tick end: &endTick];
		if (tick < 0) {
			tick = 0;
			position = 0;
		}
	} else {
		position = [self eventPositionForTableRow: row];
		ep = [self eventPointerForTableRow: row];
		if (ep != NULL) {
			/*  An event is selected: a new event is inserted after the selected event
				with the same tick, and this new event is edited  */
			tick = MDGetTick(ep);
			position++;
		} else {
			/*  End of track is selected: a new event is inserted at the end of track
				and this new event is edited  */
			tick = MDTrackGetDuration(myTrack);
		}
	}
	[self startEditAtColumn: -1 creatingEventWithTick: tick atPosition: position];
}

- (IBAction)editSelectedEvent: (id)sender
{
	int row = [myEventTrackView selectedRow];
	if (row >= 0)
		[self startEditAtColumn: -1 row: row];
}

#pragma mark ====== Other UI ======

- (void)editingRangeChanged: (NSNotification *)notification
{
	[self updateEditingRangeText];
}

- (IBAction)editingRangeTextModified: (id)sender
{
	BOOL startFlag;
	long bar, beat, subtick;
	MDTickType tick, duration, endtick;
	const char *s;
	if (sender == startEditingRangeText)
		startFlag = YES;
	else startFlag = NO;
	s = [[sender stringValue] UTF8String];
	if (s[0] == 0) {
		/*  Empty string: clear editing range  */
		tick = endtick = -1;
	} else {
		if (MDEventParseTickString(s, &bar, &beat, &subtick) < 3)
			return;
		tick = MDCalibratorMeasureToTick(myCalibrator, bar, beat, subtick);
		duration = [[[self document] myMIDISequence] sequenceDuration];
		if (tick < 0)
			tick = 0;
		if (tick > duration)
			tick = duration;
		if (startFlag)
			endtick = tick;
		else {
			MDTickType tick1, tick2;
			[[self document] getEditingRangeStart: &tick1 end: &tick2];
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

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void  *)contextInfo
{
	ListWindowFilterRecord *filter;
	int n;
	EventFilterPanelController *cont = [sheet windowController];
	NSEnumerator *en;
	id obj;
	
	if (returnCode != 1) {
		[cont close];
		return;
	}
	
	filter = (ListWindowFilterRecord *)calloc(sizeof(ListWindowFilterRecord), 1);
	if (filter == NULL)
		return;  /*  TODO: throw exception  */
	
	filter->mode = [cont mode];
	n = 0;
	filter->table = (void *)calloc(sizeof(filter->table[0]), 300);
	if (filter->table == NULL)
		return;  /*  TODO: throw exception  */
	if ([cont isSelectedForKey: gChannelPressureKey]) {
		filter->table[n].flag = YES;
		filter->table[n].kind = kMDEventChanPres;
		n++;
	}
	if ([cont isSelectedForKey: gNoteKey]) {
		filter->table[n].flag = YES;
		filter->table[n].kind = kMDEventNote;
		n++;
	}
	if ([cont isSelectedForKey: gPitchBendKey]) {
		filter->table[n].flag = YES;
		filter->table[n].kind = kMDEventPitchBend;
		n++;
	}
	if ([cont isSelectedForKey: gPolyPressureKey]) {
		filter->table[n].flag = YES;
		filter->table[n].kind = kMDEventKeyPres;
		n++;
	}
	if ([cont isSelectedForKey: gProgramKey]) {
		filter->table[n].flag = YES;
		filter->table[n].kind = kMDEventProgram;
		n++;
	}
	if ([cont isSelectedForKey: gSysexKey]) {
		filter->table[n].flag = YES;
		filter->table[n].kind = kMDEventSysex;
		n++;
		filter->table[n].flag = YES;
		filter->table[n].kind = kMDEventSysexCont;
		n++;
	}
	en = [[cont ccMetaFilters] objectEnumerator];
	while ((obj = [en nextObject]) != nil) {
		int num = [[obj valueForKey: gCCMetaNumberKey] intValue];
		filter->table[n].flag = [[obj valueForKey: gCCMetaSelectedKey] boolValue];
		if (num >= 128) {
			filter->table[n].kind = MDEventSMFMetaNumberToEventKind(num - 128);
			filter->table[n].data = num - 128;
		} else {
			filter->table[n].kind = kMDEventControl;
			filter->table[n].data = num;
		}
		if (n++ >= 256)
			break;
	}
	filter->table[n++].kind = kMDEventStop;
	filter->table = realloc(filter->table, sizeof(filter->table[0]) * n);
	filter->count = n;
	
	[cont close];
	
	if (myFilter != NULL) {
		if (myFilter->table != NULL)
			free(myFilter->table);
		free(myFilter);
	}
	myFilter = filter;
	myCount = -1;
	[myEventTrackView reloadData];
	[self reloadSelection];
}

- (IBAction)openEventFilterPanel: (id)sender
{
	int i;
	EventFilterPanelController *cont;
    cont = [[EventFilterPanelController allocWithZone: [self zone]] init];
	[cont window];  //  Load the nib file
	
	//  Set up the panel settings
	if (myFilter == NULL) {
		[cont setMode: 0];
	} else {
		[cont setMode: myFilter->mode];
		for (i = 0; i < myFilter->count; i++) {
			int kind = myFilter->table[i].kind;
			int n;
			id key = nil;
			if (kind == kMDEventStop)
				break;
			n = MDEventMetaKindCodeToSMFMetaNumber(kind, myFilter->table[i].data);
			if (n >= 0 && n < 128) {
				/*  Meta event  */
				[cont addNewCCMetaFilter: n + 128 selected: myFilter->table[i].flag];
				continue;
			}
			switch (kind) {
				case kMDEventControl:
					[cont addNewCCMetaFilter: myFilter->table[i].data selected: myFilter->table[i].flag];
					continue;
				case kMDEventChanPres:
					key = gChannelPressureKey; break;
				case kMDEventNote:
					key = gNoteKey; break;
				case kMDEventPitchBend:
					key = gPitchBendKey; break;
				case kMDEventKeyPres:
					key = gPolyPressureKey; break;
				case kMDEventProgram:
					key = gProgramKey; break;
				case kMDEventSysex:
				case kMDEventSysexCont:
					key = gSysexKey; break;
			}
			if (key != nil && myFilter->table[i].flag)
				[cont select: YES forKey: key];
		}
	}
	
	[[NSApplication sharedApplication] beginSheet: [cont window]
		modalForWindow: [self window]
		modalDelegate: self
		didEndSelector: @selector(sheetDidEnd:returnCode:contextInfo:)
		contextInfo: nil];
}

#pragma mark ==== Pasteboard support ====

- (void)doCopy: (BOOL)copyFlag andDelete: (BOOL)deleteFlag
{
	MDSelectionObject *sel, **selArray;
	MDTickType startTick, endTick;
	MyDocument *doc = (MyDocument *)[self document];
	int numberOfTracks = [[doc myMIDISequence] trackCount];

	if ([myEventTrackView numberOfSelectedRows] == 0)
		return;

	selArray = (MDSelectionObject **)calloc(sizeof(MDSelectionObject *), numberOfTracks);
	if (selArray == NULL)
		return;

	selArray[myTrackNumber] = [doc selectionOfTrack: myTrackNumber];
	[doc getEditingRangeStart: &startTick end: &endTick];

	if (copyFlag)
		[doc copyWithSelections: selArray rangeStart: startTick rangeEnd: endTick];

	if (deleteFlag) {
		sel = [doc selectionOfTrack: myTrackNumber];
		[doc deleteMultipleEventsAt: sel fromTrack: myTrackNumber deletedEvents: NULL];
	}
	
	free(selArray);
}

- (void)doPasteWithMergeFlag: (BOOL)mergeFlag
{
//- (BOOL)getPasteboardSequence: (MDSequence **)outSequence catalog: (MDCatalog **)outCatalog;
	MyDocument *doc = (MyDocument *)[self document];
	MDSequence *seq;
	MDCatalog *catalog;
	int targetTrack, result;

	if (![doc getPasteboardSequence: &seq catalog: &catalog])
		return;
	if (catalog->num != 1) {
		NSRunCriticalAlertPanel(@"Cannot paste", @"You are trying to paste multiple tracks in this single-track window. Please try pasting in the graphic window or try copying again.", @"OK", @"", @"");
		return;
	}
	
	targetTrack = myTrackNumber;
	result = [doc doPaste: seq toTracks: &targetTrack rangeStart: catalog->startTick rangeEnd: catalog->endTick mergeFlag: mergeFlag];
	
	switch (result) {
		case 1:  /*  Trying to paste MIDI track to the conductor track  */
			NSRunCriticalAlertPanel(@"Cannot paste", @"You are trying to paste a MIDI track to the conductor track. Please try pasting in another window or try copying again.", @"OK", @"", @"");
			break;
	}

	free(catalog);
	MDSequenceRelease(seq);
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
	[self doPasteWithMergeFlag: YES];
}

- (IBAction)pasteWithReplace: (id)sender
{
	[self doPasteWithMergeFlag: NO];
}

- (IBAction)merge: (id)sender
{
	[self doPasteWithMergeFlag: YES];
}

- (BOOL)validateUserInterfaceItem: (id)anItem
{
	SEL sel = [anItem action];
	if (sel == @selector(copy:) || sel == @selector(cut:) || sel == @selector(delete:)) {
		if ([myEventTrackView numberOfSelectedRows] > 0)
			return YES;
		else return NO;
	} else if (sel == @selector(paste:) || sel == @selector(pasteWithReplace:) || sel == @selector(merge:)) {
		if ([[self document] isSequenceInPasteboard])
			return YES;
		else return NO;
	} else return YES;
}

@end
