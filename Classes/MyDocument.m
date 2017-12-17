//
//  MyDocument.m
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

#import "MyDocument.h"
//#import "TrackWindowController.h"
#import "NSWindowControllerAdditions.h"
#import "MyMIDISequence.h"
#import "LoadingPanelController.h"
#import "RemapDevicePanelController.h"
//#import "PlayingPanelController.h"
#import "MDObjects.h"
#import "GraphicWindowController.h"
#import "PlayingViewController.h"
#import "MyAppController.h"
#import "QuantizePanelController.h"

#include "MDRubyExtern.h"

NSString *MyDocumentTrackModifiedNotification = @"My Track Modified Notification";
NSString *MyDocumentTrackInsertedNotification = @"My Track Inserted Notification";
NSString *MyDocumentTrackDeletedNotification = @"My Track Deleted Notification";
NSString *MyDocumentPlayPositionNotification = @"My Track Play Position Notification";
//NSString *MyDocumentStopPlayingNotification = @"My Track Stop Playing Notification";
NSString *MyDocumentSelectionDidChangeNotification = @"My Selection Did Change Notification";
NSString *MyDocumentEditingRangeDidChangeNotification = @"My Editing Range Did Change Notification";

//  Pasteboard types
NSString *MySequencePBoardType = @"Alchemusica MIDI sequence";
NSString *MySeqCatalogPBoardType = @"Alchemusica MIDI sequence info";

/*  The following notification is used only within MyDocument  */
static NSString *sSelectionWillChangeNotification = @"My Selection Will Change Notification";
static NSString *sPostTrackModifiedNotification = @"TrackModifiedNotification needs posted later";

/*  Do runtime sanity check after every edit operations (slow)  */
#if defined(DEBUG)
#define DEFAULT_SANITY_CHECK 1
#else
#define DEFAULT_SANITY_CHECK 0
#endif
int gMyDocumentSanityCheck = DEFAULT_SANITY_CHECK;

@implementation MyDocument

#pragma mark ====== Keeping the document/track correspondence ======

static MyDocumentTrackInfo **sTrackInfos;
static int sNumTrackInfo, sMaxTrackInfo;

+ (void)registerDocumentTrackInfo: (MyDocumentTrackInfo *)info
{
	if (sTrackInfos == NULL) {
		sMaxTrackInfo = 8;
		sNumTrackInfo = 0;
		sTrackInfos = (MyDocumentTrackInfo **)malloc(sizeof(MyDocumentTrackInfo *) * sMaxTrackInfo);
	} else if (sNumTrackInfo >= sMaxTrackInfo) {
		sMaxTrackInfo += 8;
		sTrackInfos = (MyDocumentTrackInfo **)realloc(sTrackInfos, sizeof(MyDocumentTrackInfo *) * sMaxTrackInfo);
	}
	/*  TODO: check sTrackInfo != NULL  */
	sTrackInfos[sNumTrackInfo++] = info;
}

+ (void)unregisterDocumentTrackInfo: (MyDocumentTrackInfo *)info
{
	int i;
	for (i = 0; i < sNumTrackInfo; i++) {
		if (sTrackInfos[i] == info) {
			/*  Remove this entry  */
			if (i < sNumTrackInfo - 1)
				memmove(&sTrackInfos[i], &sTrackInfos[i + 1], sizeof(MyDocumentTrackInfo *) * (sNumTrackInfo - i - 1));
			sNumTrackInfo--;
			return;
		}
	}
}

#pragma mark ====== init/dealloc ======

- (id)init {
    self = [super init];
    if (self != nil) {
		int i;
        myMIDISequence = [[MyMIDISequence allocWithZone:[self zone]] initWithDocument:self];
		mainWindowController = nil;
        selections = [[NSMutableArray allocWithZone: [self zone]] init];
		/*  Set empty selection for all tracks  */
		for (i = 0; i < [myMIDISequence trackCount]; i++) {
			[selections addObject: [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease]];
		}
	//	[self setNeedsUpdateEditingRange: YES];
		[[NSNotificationCenter defaultCenter]
			addObserver: self
			selector: @selector(selectionWillChange:)
			name: sSelectionWillChangeNotification
			object: self];
		[[NSNotificationCenter defaultCenter]
			addObserver: self
			selector: @selector(postTrackModifiedNotification:)
			name: sPostTrackModifiedNotification
			object: self];
		[[NSNotificationCenter defaultCenter]
		 addObserver:self
		 selector:@selector(trackModified:)
		 name:MyDocumentTrackModifiedNotification
		 object:self];
		
		//  Create a Ruby object for this document
		MRSequenceRegister(self);
		
		startEditingRange = endEditingRange = kMDNegativeTick;
    }
    return self;
}

- (void)dealloc {
//	NSLog(@"document deallocated: %@", self);
	int i;
	for (i = 0; i < sNumTrackInfo; i++) {
		if (sTrackInfos[i]->doc == self)
			sTrackInfos[i]->doc = NULL;  //  No need to release (actually, this cannot happen)
	}
	MRSequenceUnregister(self);
    [[NSNotificationCenter defaultCenter]
        removeObserver: self];
    [[self myMIDISequence] release];
    [selections release];
    [super dealloc];
}

#pragma mark ====== File I/O ======

static int
docTypeToDocCode(NSString *docType)
{
    if ([docType isEqualToString: @"Alchemusica Project File"])
        return 1;
    else if ([docType isEqualToString: @"Standard MIDI File"])
        return 2;
    else return 0;
}

- (BOOL)encodeDocumentAttributesToFile: (NSString *)fileName
{
    NSString *arcName = [NSString stringWithFormat: @"%@/attributes", fileName];
    NSMutableArray *array;
    NSMutableDictionary *dict;
    NSEnumerator *en;
    NSWindowController *cont;
    int32_t i, n;
    dict = [NSMutableDictionary dictionary];
    
    //  Track attributes
    n = [[self myMIDISequence] trackCount];
    array = [NSMutableArray arrayWithCapacity: n];
    for (i = 0; i < n; i++) {
        MDTrack *track = [[self myMIDISequence] getTrackAtIndex: i];
        [array addObject: [NSNumber numberWithInt: (int)MDTrackGetAttribute(track)]];
    }
    [dict setObject: array forKey: @"track attributes"];
    
    //  Windows
    en = [[self windowControllers] objectEnumerator];
    array = [NSMutableArray array];
    while ((cont = (NSWindowController *)[en nextObject]) != nil) {
        [array addObject: [cont encodeWindow]];
    }
    [dict setObject: array forKey: @"windows"];

    return [NSKeyedArchiver archiveRootObject: dict toFile: arcName];
}

- (BOOL)decodeDocumentAttributesFromFile: (NSString *)fileName
{
//    NSString *arcName = [NSString stringWithFormat: @"%@/attributes", fileName];
//    NSDictionary *dict = [NSKeyedUnarchiver unarchiveObjectWithFile: arcName];
//    NSLog(@"archive = %@", dict);
    return YES;
}

static int
callback(float progress, void *data)
{
	LoadingPanelController *controller = (LoadingPanelController *)data;
	[controller setProgressAmount: (double)progress];
	if (![controller runSession] || [controller canceled])
		return 0;
	else return 1;
}

/*  ファイルを読み込み、そのあと Remap device ダイアログをシートとして表示する。  */
- (BOOL)readFromFile:(NSString *)fileName ofType:(NSString *)docType
{
    int i, n;
	MDStatus result;
	LoadingPanelController *controller;
	RemapDevicePanelController *remapController;
    NSString *smfName;
	NSString *title = NSLocalizedString(@"Alchemusica: Loading...", @"");
	NSString *caption = [NSString stringWithFormat: NSLocalizedString(@"Loading %@...", @""), [fileName lastPathComponent]];
	int docCode = docTypeToDocCode(docType);

	//  Create progress panel
	controller = [[LoadingPanelController allocWithZone: [self zone]] initWithTitle: title andCaption: caption];
	
	//  Begin a modal session
	[controller beginSession];
	
	//  Read SMF, periodically invoking callback
    if (docCode == 1)
        smfName = [NSString stringWithFormat: @"%@/Sequence.mid", fileName];
    else smfName = fileName;
	result = [myMIDISequence readSMFFromFile: smfName withCallback: callback andData: controller];

	//  End modal session (without closing the window)
	[controller endSession];
	
	if (result == kMDNoError) {
	
        NSMutableArray *array = [NSMutableArray array];

        //  Set destination numbers for each track
		n = [myMIDISequence trackCount];
        for (i = 0; i < n; i++) {
            char name[256];
            MDTrack *track = [myMIDISequence getTrackAtIndex: i];
            MDTrackGetDeviceName(track, name, sizeof name);
            if (name[0] != 0) {
                int32_t dev = MDPlayerGetDestinationNumberFromName(name);
                if (dev >= 0)
                    MDTrackSetDevice(track, dev);
                else
                    [array addObject: [NSNumber numberWithInt: i]];
            }
        }
        if ([array count] > 0) {
            //  Some tracks needs remapping
            //  Restart a modal session with the same window
            [controller beginSession];
        
            //  Create a sheet to remap the device
            remapController = [[[RemapDevicePanelController allocWithZone: [self zone]]
                                    initWithDocument: self trackSelection: array] autorelease];
            
            //  Display and handle the "remap device" sheet. stopModalWithCode: is invoked when done.
            [remapController beginSheetForWindow: [controller window] invokeStopModalWhenDone: YES];
            
            //  Wait until stopModalWithCode: is invoked
            while ([controller runSession])
                ;
            
            //  End modal session
            [controller endSession];
        }
	}
	
	//  Close progress panel
	[controller close];
	
    //  Initialize selections
    if (result == kMDNoError) {
        [selections removeAllObjects];
        for (i = [myMIDISequence trackCount] - 1; i >= 0; i--) {
            id obj = [[MDSelectionObject allocWithZone: [self zone]] init];
            if (obj == nil) {
                result = kMDErrorOutOfMemory;
                break;
            }
            [selections addObject: obj];
            [obj release];
        }
    }

	return (result == kMDNoError);
}

- (BOOL)writeToFile:(NSString *)fileName ofType:(NSString *)docType
{
	MDStatus result;
	LoadingPanelController *controller;
	NSString *title = NSLocalizedString(@"Alchemusica: Saving...", @"");
	NSString *caption = [NSString stringWithFormat: NSLocalizedString(@"Saving %@...", @""), [fileName lastPathComponent]];
	NSString *smfName;
    int docCode = docTypeToDocCode(docType);

    if (docCode == 0)
        return NO;

    //  Create a new directory if necessary
    if (docCode == 1) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath: fileName withIntermediateDirectories: YES attributes: nil error:NULL])
            return NO;
        /*  TODO: Make it package <-- not necessary! (Info.plist description is enough)  */
    }
    
	//  Create progress panel
	controller = [[LoadingPanelController allocWithZone: [self zone]] initWithTitle: title andCaption: caption];

	//  Begin a modal session
	[controller beginSession];
	
	//  Write SMF, periodically invoking callback
    if (docCode == 1)
        smfName = [NSString stringWithFormat: @"%@/Sequence.mid", fileName];
    else smfName = fileName;
	result = [myMIDISequence writeSMFToFile: smfName withCallback: callback andData: controller];

    //  Archive window informations
    if (result == kMDNoError && docCode == 1) {
        result = ([self encodeDocumentAttributesToFile: fileName] ? kMDNoError : kMDErrorCannotWriteToStream);
    }

	//  End modal session and close the panel
	[[controller endSession] close];

	return (result == kMDNoError);
}

#pragma mark ====== Handling windows ======

- (void)makeWindowControllers
{
    int docCode = docTypeToDocCode([self fileType]);
    mainWindowController = [[[GraphicWindowController allocWithZone:[self zone]] init] autorelease];
    [self addWindowController: mainWindowController];
    if (docCode == 1)
        [self decodeDocumentAttributesFromFile: [[self fileURL] path]];
    [[mainWindowController window] makeKeyAndOrderFront: self];
    [[mainWindowController window] makeFirstResponder: [[mainWindowController window] initialFirstResponder]];
}

- (void)createWindowForTracks: (NSArray *)tracks ofType: (NSString *)windowType
{
	NSEnumerator *en;
	id obj;
    int track;
    Class class;
    NSWindowController *cont;

    class = [NSWindowController classForWindowType: windowType];
    if (class == nil)
        return;    
    if (![class canContainMultipleTracks]) {
        //  Open window for each track
        en = [tracks objectEnumerator];
        while ((obj = [en nextObject]) != nil) {
            NSEnumerator *enWin;
            if (![obj isKindOfClass: [NSNumber class]])
                continue;
            track = [obj intValue];
            //  Examine whether the requested track is already open
            enWin = [[self windowControllers] objectEnumerator];
			while ((cont = (NSWindowController *)[enWin nextObject]) != nil) {
				if ([cont isKindOfClass: class] && [cont containsTrack: track])
					break;
			}
			if (cont == nil) {
				//  Create a new window controller
				cont = [[[class allocWithZone:[self zone]] init] autorelease];
				if (cont != nil) {
					[self addWindowController: cont];
					[cont window];  /*  Load window  */
					[cont addTrack: track];
				}
			}
            if (cont != nil) {
                [[cont window] makeKeyAndOrderFront: self];
                [cont reloadSelection];
                [[cont window] makeFirstResponder: [[cont window] initialFirstResponder]];
            }
        }
    } else {
        //  Open one window with all tracks
        cont = [[[class allocWithZone: [self zone]] init] autorelease];
        if (cont != nil) {
			int lastTrack;
            [self addWindowController: cont];
            en = [tracks objectEnumerator];
            while ((obj = [en nextObject]) != nil) {
				lastTrack = [obj intValue];
                [cont addTrack: lastTrack];
				[cont setFocusFlag: YES onTrack: lastTrack extending: YES];
			}
            [[cont window] makeKeyAndOrderFront: self];
            [cont reloadSelection];
            [[cont window] makeFirstResponder: [[cont window] initialFirstResponder]];
        }
    }
}

#pragma mark ====== Handling MyMIDISequence ======

- (MyMIDISequence *)myMIDISequence {
    return myMIDISequence;
}

- (NSString *)tuneName {
	return [self displayName];
//	NSString *name = [self fileName];
//	if (name != nil)
//		return [name lastPathComponent];
//	else {
//		name = [[mainWindowController window] title];
//		if (name != nil)
//			return name;
//		else return @"";
//	}
}

- (float)timebase
{
	MDSequence *sequence = [[self myMIDISequence] mySequence];
	if (sequence == NULL)
		return 480.0f;
	else return (float)MDSequenceGetTimebase(sequence);
}

- (void)setTimebase:(float)timebase
{
	MDSequence *sequence = [[self myMIDISequence] mySequence];
	if (sequence == NULL)
		return;
	
	//  Register undo action
	[[[self undoManager] prepareWithInvocationTarget: self]
	 setTimebase: (float)MDSequenceGetTimebase(sequence)];
	MDSequenceSetTimebase(sequence, (int32_t)timebase);
}

- (void)lockMIDISequence
{
	MDSequence *sequence = [[self myMIDISequence] mySequence];
	MDSequenceLock(sequence);
}

- (void)unlockMIDISequence
{
	MDSequence *sequence = [[self myMIDISequence] mySequence];
	MDSequenceUnlock(sequence);
}

#pragma mark ====== Color management ======

- (NSColor *)colorForTrack: (int)track enabled: (BOOL)flag
{
	NSColor *color;
	color = [NSColor colorWithDeviceHue: (float)(track * 2 % 31) / 31.0f saturation: 1.0f brightness: 1.0f - 0.1f * (track / 31) alpha: (flag ? 1.0f : 0.5f)];
//	if (!flag)
//		color = [color shadowWithLevel: 0.5];
	return color;
}

+ (NSColor *)colorForEditingRange
{
	static NSColor *sColorEditingRange;
	if (sColorEditingRange == nil) {
		sColorEditingRange = [[NSColor colorWithDeviceRed: 1.0f green: 0.9f blue: 1.0f alpha: 1.0f] retain];
	}
	return sColorEditingRange;
}

+ (NSColor *)colorForSelectingRange
{
	static NSColor *sColorSelectingRange;
	if (sColorSelectingRange == nil) {
		sColorSelectingRange = [[NSColor colorWithDeviceRed: 0.5f green: 0.5f blue: 1.0f alpha: 1.0f] retain];
	}
	return sColorSelectingRange;
}

#pragma mark ====== Selection undo/redo ======

static NSString *sEditingRangeKey = @"editing_range";
static NSString *sStackShouldBeCleared = @"stack_should_be_cleared";

- (void)getSelectionStartTick: (MDTickType *)startTickPtr endTick: (MDTickType *)endTickPtr editableTracksOnly: (BOOL)flag
{
	int i;
	int ntracks = (int)[selections count];
	MDTickType startTick, endTick;
	MyMIDISequence *seq = [self myMIDISequence];

	startTick = kMDMaxTick;
	endTick = kMDNegativeTick;
	for (i = 0; i < ntracks; i++) {
		MDTickType startTick1, endTick1;
		MDSelectionObject *selection;
		if (flag && ([self trackAttributeForTrack: i] & kMDTrackAttributeEditable) == 0)
			continue;
		selection = (MDSelectionObject *)[selections objectAtIndex: i];
		if ([selection getStartTick: &startTick1 andEndTick: &endTick1 withMDTrack: [seq getTrackAtIndex: i]] && startTick1 >= 0 && endTick1 >= 0) {
			if (startTick1 < startTick)
				startTick = startTick1;
			if (endTick1 > endTick)
				endTick = endTick1;
		}
	}
	if (startTick < kMDMaxTick) {
		*startTickPtr = startTick;
		*endTickPtr = endTick;
	} else {
		*startTickPtr = *endTickPtr = kMDNegativeTick;
	}
}

/*  Recalculate the editing range from the current selections:
	This is called from the notification handler for sSelectionWillChangeNotification  */
- (void)updateEditingRange
{
	//  Calculate the editing range from the selections
	[self getSelectionStartTick: &startEditingRange endTick: &endEditingRange editableTracksOnly: NO];
}

/*  Enqueue undo information for selection change  */
/*  At idle time, a "coalesced" notification is sent to self and selectionWillChange: is called */
- (void)enqueueSelectionUndoerWithKey: (id)key value: (id)value
{
	if (selectionQueue == nil)
		selectionQueue = [[NSMutableDictionary dictionary] retain];
	if ([selectionQueue objectForKey: key] == nil)
		[selectionQueue setObject: value forKey: key];
	[[NSNotificationQueue defaultQueue]
		enqueueNotification:
			[NSNotification notificationWithName: sSelectionWillChangeNotification object: self]
		postingStyle: NSPostWhenIdle 
		coalesceMask: (NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender)
		forModes: nil];
}

/*  Notification handler for (internal) sSelectionWillChangeNotification  */
- (void)selectionWillChange: (NSNotification *)notification
{
	id keys;
	int i;
	BOOL isEditingRangeModified = NO;

	if (selectionQueue == nil)
		return;

	/*  This will be later used in notification  */
	keys = [[[selectionQueue allKeys] retain] autorelease];

	if ([selectionQueue objectForKey: sStackShouldBeCleared] != nil) {
		/*  If any track is modified then the selection undo stack is cleared.
			No recalc of the editing range occurs, and selectionQueue is discarded. */
		[selectionStack release];
		selectionStack = nil;
		selectionStackPointer = 0;
		isEditingRangeModified = NO;
	} else {
		/*  Otherwise, selectionQueue is inserted at selectionStack[selectionStackPointer].
			If selectionStackPointer < [count selectionStack], then the elements at indices 
			no less than selectionStackPointer are discarded.  */
		if (selectionStack == nil)
			selectionStack = [[NSMutableArray array] retain];
		if (selectionStackPointer < [selectionStack count]) {
			[selectionStack removeObjectsInRange: NSMakeRange(selectionStackPointer, [selectionStack count] - selectionStackPointer)];
		}
		[selectionStack addObject: selectionQueue];
		isEditingRangeModified = [keys containsObject: sEditingRangeKey];
		/*  If selection is modified and editing range is not touched, then new editing range 
			is calculated from the new selection. */
		for (i = (int)[keys count] - 1; i >= 0; i--) {
			if ([[keys objectAtIndex: i] isKindOfClass: [NSNumber class]])
				break;
		}
		if (i >= 0 && !isEditingRangeModified) {
			[self updateEditingRange];
			isEditingRangeModified = YES;
		}
	}

	/*  SelectionDidChange notification is sent with [selectionQueue allKeys] as the object.  */
	[[NSNotificationCenter defaultCenter]
		postNotificationName: MyDocumentSelectionDidChangeNotification
		object: self
		userInfo: [NSDictionary
			dictionaryWithObjectsAndKeys: keys, @"keys", nil]];

	/*  EditingRangeDidChange notification is sent as the object.  */
	[[NSNotificationCenter defaultCenter]
		postNotificationName: MyDocumentEditingRangeDidChangeNotification
		object: self userInfo: nil];
	
	[selectionQueue release];
	selectionQueue = nil;	
}


#pragma mark ====== Posting notifications ======

- (void)postTrackModifiedNotification: (NSNotification *)notification
{
	int i;

	/*  Post track modified notification for all modified tracks  */
	for (i = (int)[modifiedTracks count] - 1; i >= 0; i--) {
		int32_t trackNo = [[modifiedTracks objectAtIndex: i] intValue];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MyDocumentTrackModifiedNotification
			object:self
			userInfo:[NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithLong: trackNo], @"track", nil]];
	}
	[modifiedTracks release];
	modifiedTracks = nil;
	
	if (notification == nil) {
		//  Dequeue "sPostTrackModifiedNotification" notifications
		[[NSNotificationQueue defaultQueue]
			dequeueNotificationsMatching:
				[NSNotification notificationWithName: sPostTrackModifiedNotification object: self]
			coalesceMask: (NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender)];
	}
}

- (void)enqueueTrackModifiedNotification: (int32_t)trackNo
{
	int i;

	/*  Calibrators should be reset  */
	MDSequenceResetCalibrators([myMIDISequence mySequence]);

	/*  Add a track to the modifiedTracks array (if not already present)  */
	for (i = (int)[modifiedTracks count] - 1; i >= 0; i--) {
		if ([[modifiedTracks objectAtIndex: i] intValue] == trackNo)
			break;
	}
	if (i < 0) {
		if (modifiedTracks == nil)
			modifiedTracks = [[NSMutableArray array] retain];
		[modifiedTracks addObject: [NSNumber numberWithLong: trackNo]];
	}
	
	/*  Post an internal notification that requests sending a "real" notification 
		at the end of the runloop  */
	[[NSNotificationQueue defaultQueue]
		enqueueNotification:
			[NSNotification notificationWithName: sPostTrackModifiedNotification object: self]
		postingStyle: NSPostWhenIdle 
		coalesceMask: (NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender)
		forModes: nil];
	
	/*  Update editing range  */
	[self updateEditingRange];
	
	/*  Any track modification should clear the selection undo stack  */
	[self enqueueSelectionUndoerWithKey: sStackShouldBeCleared value: sStackShouldBeCleared];
}

- (void)postPlayPositionNotification: (MDTickType)tick
{
	float beat;
//	if ([[self myMIDISequence] isPlaying])
//		beat = [[self myMIDISequence] playingBeat];
//	else beat = -1.0;
	beat = tick / [self timebase];
	[[NSNotificationCenter defaultCenter]
		postNotificationName: MyDocumentPlayPositionNotification
		object: self
		userInfo: [NSDictionary
			dictionaryWithObjectsAndKeys: [NSNumber numberWithFloat: beat], @"position", nil]];
}

- (void)trackModified: (NSNotification *)notification {
	if (gMyDocumentSanityCheck) {
		int32_t trackNo = [[[notification userInfo] objectForKey: @"track"] intValue];
		MDTrack *track = [[self myMIDISequence] getTrackAtIndex:trackNo];
		if (MDTrackRecache(track, 1) > 0) {
			MyAppCallback_messageBox("Track data has some inconsistency", "Internal Error", 0, 0);
		}
	}
}

- (void)trackInserted: (NSNotification *)notification {
}

- (void)trackDeleted: (NSNotification *)notification {
}

- (void)documentSelectionDidChange: (NSNotification *)notification {
}

//- (void)postSelectionDidChangeNotification: (int32_t)trackNo selectionChange: (IntGroupObject *)set sender: (id)sender
//{
//	[[NSNotificationCenter defaultCenter]
//		postNotificationName:MyDocumentSelectionDidChangeNotification
//		object:self
//		userInfo:[NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithLong: trackNo], @"track", set, @"selectionChange", sender, @"sender", nil]];
//}

//- (void)postEditingRangeDidChangeNotification
//{
//	[[NSNotificationCenter defaultCenter]
//		postNotificationName:MyDocumentEditingRangeDidChangeNotification
//		object: self
//		userInfo: nil];
//}

/*
- (void)postStopPlayingNotification
{
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MyDocumentStopPlayingNotification
		object:self
		userInfo: nil];
}
*/

/*- (void)midiSetupDidChange: (NSNotification *)aNotification
{
}
*/

#pragma mark ====== Editing track lists ======

- (BOOL)insertTrack: (MDTrackObject *)trackObj atIndex: (int32_t)trackNo
{
	MDTrack *track;
	MDSequence *sequence;
    NSData *attr;
	int32_t index;
	if (trackObj == nil) {
		trackObj = [[[MDTrackObject allocWithZone:[self zone]] init] autorelease];
	}
	track = trackObj->track;
	sequence = [[self myMIDISequence] mySequence];
    attr = [self getTrackAttributes];
	index = MDSequenceInsertTrack(sequence, trackNo, track);
	if (index >= 0) {
        /*  Update selections  */
        [selections insertObject: [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease] atIndex: trackNo];
		/*  Register undo action (delete and restore track attributes) */
        [[[self undoManager] prepareWithInvocationTarget: self]
            setTrackAttributes: attr];
		[[[self undoManager] prepareWithInvocationTarget: self]
			deleteTrackAt: index];
		/*  Post pending notifications for track modification  */
		[self postTrackModifiedNotification: nil];
		/*  Post a notification that a track has been inserted  */
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MyDocumentTrackInsertedNotification
			object:self
			userInfo:[NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithLong: index], @"track", nil]];

		/*  Update registered document/track info  */
		{
			int i;
			for (i = 0; i < sNumTrackInfo; i++) {
				if (sTrackInfos[i]->doc == self) {
					if (sTrackInfos[i]->num >= index) {
						sTrackInfos[i]->num++;
					}
				}
				if (sTrackInfos[i]->track == track) {
					if (sTrackInfos[i]->doc != self)
						sTrackInfos[i]->doc = self;
					sTrackInfos[i]->num = index;
				}
			}
		}

		return YES;
	} else return NO;
}

- (BOOL)deleteTrackAt: (int32_t)trackNo
{
	MDTrack *track;
	MDSequence *sequence;
    NSData *attr;
	int32_t index;
	sequence = [[self myMIDISequence] mySequence];
	track = MDSequenceGetTrack(sequence, trackNo);
	if (track != NULL) {
		MDSelectionObject *psetObj = [self selectionOfTrack: trackNo];
		MDTrackObject *trackObj;

		/*  Update registered document/track info  */
		{
			int i, j;
			j = -1;
			for (i = 0; i < sNumTrackInfo; i++) {
				if (sTrackInfos[i]->track == track) {
					j = i;  /*  track is used elsewhere  */
					if (sTrackInfos[i]->doc == self)
						sTrackInfos[i]->doc = NULL;
				}
				if (sTrackInfos[i]->doc == self) {
					if (sTrackInfos[i]->num > trackNo)
						sTrackInfos[i]->num--;
				}
			}
			if (j >= 0) {
				/*  Duplicate track for undo  */
				MDTrack *track2 = MDTrackNewFromTrack(track);
				if (track2 != NULL)
					track = track2;
			}
		}
		
		trackObj = [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: track] autorelease];
        attr = [self getTrackAttributes];
		index = MDSequenceDeleteTrack(sequence, trackNo);
		/*  Register undo action (insert, restore track attributes and selection)  */
		[[[self undoManager] prepareWithInvocationTarget: self]
			setSelection: psetObj inTrack: trackNo sender: self];
        [[[self undoManager] prepareWithInvocationTarget: self]
            setTrackAttributes: attr];
		[[[self undoManager] prepareWithInvocationTarget: self]
			insertTrack: trackObj atIndex: trackNo];
        /*  Update selections  */
        [selections removeObjectAtIndex: trackNo];
		/*  Post pending notifications for track modification  */
		[self postTrackModifiedNotification: nil];
		/*  Post a notification that a track has been deleted  */
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MyDocumentTrackDeletedNotification
			object:self
			userInfo:[NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithLong: index], @"track", nil]];

		return YES;
	} else return NO;
}

#pragma mark ====== Editing track informations ======

- (BOOL)updateTrackDestinations
{
    MDPlayer *player = [[self myMIDISequence] myPlayer];
    MDPlayerStatus status = MDPlayerGetStatus(player);
    if (status == kMDPlayer_playing || status == kMDPlayer_suspended) {
        if (MDPlayerRefreshTrackDestinations(player) != kMDNoError) {
            /*  Something wrong: stop playing and returns NO  */
        /*    [[PlayingPanelController sharedPlayingPanelController] pressStopButton: self]; */
            return NO;
        }
        return YES;
    }
    return NO;
}

//  Get names of all destinations and the currently used device names.
//  Duplicates are removed. Existing destinations (regardless they are used or not) are stored first.
- (NSArray *)getDestinationNames
{
	int i, n;
	char name[256];
	MDTrack *track;
	NSMutableArray *array = [NSMutableArray array];
	id aname;
	n = MDPlayerGetNumberOfDestinations();
	[array addObject:@""];  //  The first object is always an empty string
	for (i = 0; i < n; i++) {
		MDPlayerGetDestinationName(i, name, sizeof name);
		aname = [NSString localizedStringWithFormat:@"%s", name];
		if (![array containsObject:aname])
			[array addObject:aname];
	}
	n = [myMIDISequence trackCount];
	for (i = 0; i < n; i++) {
		track = [myMIDISequence getTrackAtIndex: i];
        MDTrackGetDeviceName(track, name, sizeof name);
		aname = [NSString localizedStringWithFormat:@"%s", name];
		if (![array containsObject:aname])
			[array addObject:aname];
	}
	if (destinationNames != nil) {
		n = (int)[destinationNames count];
		for (i = 0; i < n; i++) {
			aname = [destinationNames objectAtIndex:i];
			if (![array containsObject:aname])
				[array addObject:aname];
		}
	}
	destinationNames = [array retain];
	return array;
}

- (NSData *)getTrackAttributes
{
    MDTrack *track;
    MDSequence *sequence;
    int32_t n, i;
    NSMutableData *data;
    MDTrackAttribute *ap;
    sequence = [[self myMIDISequence] mySequence];
    if (sequence == NULL)
        return nil;
    n = MDSequenceGetNumberOfTracks(sequence);
    data = [NSMutableData dataWithLength: sizeof(MDTrackAttribute) * n];
    ap = (MDTrackAttribute *)[data mutableBytes];
    for (i = 0; i < n; i++) {
        track = MDSequenceGetTrack(sequence, i);
        *ap++ = (track != NULL ? MDTrackGetAttribute(track) : 0);
    }
    return data;
}

- (void)setTrackAttributes: (NSData *)data
{
    MDTrack *track;
    MDSequence *sequence;
    int32_t n, i;
    const MDTrackAttribute *ap;
    sequence = [[self myMIDISequence] mySequence];
    if (sequence == NULL)
        return;
    n = MDSequenceGetNumberOfTracks(sequence);
    i = (int)([data length] / sizeof(MDTrackAttribute));
    if (i < n)
        n = i;
    ap = (const MDTrackAttribute *)[data bytes];
    for (i = 0; i < n; i++) {
        track = MDSequenceGetTrack(sequence, i);
        if (track != NULL)
            MDTrackSetAttribute(track, ap[i]);
    }
}

- (MDTrackAttribute)trackAttributeForTrack: (int32_t)trackNo
{
	MDSequence *seq;
	MDTrack *track;
	seq = [[self myMIDISequence] mySequence];
	if (seq != NULL && (track = MDSequenceGetTrack(seq, trackNo)) != NULL)
		return MDTrackGetAttribute(track);
	else return 0;
}

- (void)setTrackAttribute: (MDTrackAttribute)attr forTrack: (int32_t)trackNo
{
	MDSequence *seq;
	MDTrack *track;
	seq = [[self myMIDISequence] mySequence];
	if (seq != NULL && (track = MDSequenceGetTrack(seq, trackNo)) != NULL) {
		MDTrackAttribute oldAttr = MDTrackGetAttribute(track);
		if (oldAttr != attr) {
			MDTrackSetAttribute(track, attr);
			[[[self undoManager] prepareWithInvocationTarget: self]
				setTrackAttribute: oldAttr forTrack: trackNo];
			[self enqueueTrackModifiedNotification: trackNo];
		}
	}	
}

- (BOOL)isTrackSelected: (int32_t)trackNo
{
	return [mainWindowController isTrackSelected: trackNo];
}

- (void)setIsTrackSelected: (int32_t)trackNo flag: (BOOL)flag
{
	[mainWindowController setIsTrackSelected: trackNo flag: flag];
}

- (BOOL)setRecordFlagOnTrack: (int32_t)trackNo flag: (int)flag
{
    MDSequence *sequence = [[self myMIDISequence] mySequence];
    if (sequence != NULL) {
        NSData *attr = [self getTrackAttributes];
        if (MDSequenceSetRecordFlagOnTrack(sequence, trackNo, flag)) {
            [[[self undoManager] prepareWithInvocationTarget: self]
                setTrackAttributes: attr];
            [self enqueueTrackModifiedNotification: trackNo];
            [self updateTrackDestinations];
            return YES;
        }
    }
    return NO;
}

- (BOOL)setMuteFlagOnTrack: (int32_t)trackNo flag: (int)flag
{
    MDSequence *sequence = [[self myMIDISequence] mySequence];
    if (sequence != NULL) {
        NSData *attr = [self getTrackAttributes];
        if (MDSequenceSetMuteFlagOnTrack(sequence, trackNo, flag)) {
            [[[self undoManager] prepareWithInvocationTarget: self]
                setTrackAttributes: attr];
       //     [self enqueueTrackModifiedNotification: trackNo];
       //     [self updateTrackDestinations];
            return YES;
        }
    }
    return NO;
}

- (BOOL)setSoloFlagOnTrack: (int32_t)trackNo flag: (int)flag
{
    MDSequence *sequence = [[self myMIDISequence] mySequence];
    if (sequence != NULL) {
        NSData *attr = [self getTrackAttributes];
        if (MDSequenceSetSoloFlagOnTrack(sequence, trackNo, flag)) {
            [[[self undoManager] prepareWithInvocationTarget: self]
                setTrackAttributes: attr];
        //    [self enqueueTrackModifiedNotification: trackNo];
        //    [self updateTrackDestinations];
            return YES;
        }
    }
    return NO;
}

- (void)registerUndoChangeTrackDuration: (int32_t)oldDuration ofTrack: (int32_t)trackNo
{
	MDTrack *track;
	MDTickType duration;
	track = [[self myMIDISequence] getTrackAtIndex: trackNo];
	duration = MDTrackGetDuration(track);
	if (oldDuration != duration)
		[[[self undoManager] prepareWithInvocationTarget: self]
			changeTrackDuration: oldDuration ofTrack: trackNo];
}

- (void)updateDeviceNumberForTrack: (int32_t)trackNo
{
	MDTrack *track = [myMIDISequence getTrackAtIndex: trackNo];
	if (track != NULL) {
		char name[256];
		MDTrackGetDeviceName(track, name, sizeof name);
		int32_t deviceNumber = MDPlayerGetDestinationNumberFromName(name);
		MDTrackSetDevice(track, deviceNumber);
	}
}

- (BOOL)changeDevice: (NSString *)deviceName forTrack: (int32_t)trackNo
{
	char name[256], oldname[256];
	MDTrack *track = [myMIDISequence getTrackAtIndex: trackNo];
	if (track != NULL && deviceName != nil) {
        MDTrackGetDeviceName(track, oldname, sizeof oldname);
		strncpy(name, [deviceName UTF8String], 255);
		name[255] = 0;
		if (strcmp(name, oldname) == 0)
			return NO;  /*  Do nothing  */
        MDTrackSetDeviceName(track, name);
        [[[self undoManager] prepareWithInvocationTarget: self]
            changeDevice: [NSString stringWithUTF8String: oldname] forTrack: trackNo];
        [self updateDeviceNumberForTrack: trackNo];
		[self enqueueTrackModifiedNotification: trackNo];
        return YES;
	} else return NO;
}

/*
- (BOOL)changeDevice: (NSString *)deviceName deviceNumber: (int32_t)deviceNumber forTrack: (int32_t)trackNo
{
	char name[256], oldname[256];
	int32_t oldnumber;
	MDTrack *track = [myMIDISequence getTrackAtIndex: trackNo];
	if (track != NULL) {
        MDTrackGetDeviceName(track, oldname, sizeof oldname);
        oldnumber = MDTrackGetDevice(track);
        if (deviceName != nil) {
            strncpy(name, [deviceName cString], 255);
            name[255] = 0;
        } else if (deviceNumber >= 0) {
            if (MDPlayerGetDestinationName(deviceNumber, name, sizeof name) != kMDNoError)
                return NO;
        }
        if (deviceNumber == -2)
            deviceNumber = MDPlayerGetDestinationNumberFromName(name);
        if (oldnumber == deviceNumber)
            return NO;	//  No need to change
        if (deviceNumber >= 0)
            MDTrackSetDevice(track, deviceNumber);
        MDTrackSetDeviceName(track, name);
        [[[self undoManager] prepareWithInvocationTarget: self]
            changeDevice: [NSString stringWithCString: oldname] deviceNumber: oldnumber forTrack: trackNo];
		[self enqueueTrackModifiedNotification: trackNo];
        [self updateTrackDestinations];
        return YES;
	}
	return NO;
}
*/

- (BOOL)changeTrackChannel: (int)channel forTrack: (int32_t)trackNo
{
    int oldchannel;
    MDTrack *track;
    if (channel >= 0 && channel < 16 && (track = [myMIDISequence getTrackAtIndex: trackNo]) != NULL) {
        oldchannel = MDTrackGetTrackChannel(track);
        if (channel == oldchannel)
            return NO;
        MDTrackSetTrackChannel(track, channel);
        [[[self undoManager] prepareWithInvocationTarget: self]
            changeTrackChannel: oldchannel forTrack: trackNo];
		[self enqueueTrackModifiedNotification: trackNo];
        [self updateTrackDestinations];
        return YES;
    }
    return NO;
}

- (BOOL)changeTrackName: (NSString *)trackName forTrack: (int32_t)trackNo
{
	char name[256], oldname[256];
	MDTrack *track;
	if (trackName != nil && (track = [myMIDISequence getTrackAtIndex: trackNo]) != NULL) {
        MDTrackGetName(track, oldname, sizeof oldname);
        strncpy(name, [trackName UTF8String], 255);
        name[255] = 0;
        if (strcmp(name, oldname) == 0)
            return NO;
        MDTrackSetName(track, name);
        [[[self undoManager] prepareWithInvocationTarget: self]
            changeTrackName: [NSString stringWithUTF8String: oldname] forTrack: trackNo];
		[self enqueueTrackModifiedNotification: trackNo];
        return YES;
	}
	return NO;
}

- (BOOL)changeTrackDuration: (int32_t)duration ofTrack: (int32_t)trackNo
{
	MDTrack *track = MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo);
	if (track != NULL) {
		int32_t tduration = MDTrackGetLargestTick(track);
		int32_t oduration = MDTrackGetDuration(track);
		if (tduration >= duration)
            duration = tduration + 1;
		if (oduration != duration) {
			MDTrackSetDuration(track, duration);
			/*  Register undo action with current value  */
			[[[self undoManager] prepareWithInvocationTarget: self]
				changeTrackDuration: oduration ofTrack: (int32_t)trackNo];
			/*  Post the notification that any track has been modified  */
			[self enqueueTrackModifiedNotification: trackNo];
			return YES;
		}
	}
	return NO;
}

#pragma mark ====== Editing events ======

- (BOOL)insertEvent: (MDEventObject *)eventObj toTrack: (int32_t)trackNo
{
	MDTrack *track;
	MDPointer *ptr;
	MDStatus sts;
	int32_t position;
	track = [[self myMIDISequence] getTrackAtIndex: trackNo];
	if (track != NULL) {
		ptr = MDPointerNew(track);
		if (ptr != NULL) {
			MDTickType oduration;
			[self lockMIDISequence];
			MDPointerSetPosition(ptr, eventObj->position);
			oduration = MDTrackGetDuration(track);
            sts = MDPointerInsertAnEvent(ptr, &eventObj->event);
			position = MDPointerGetPosition(ptr);
			[self unlockMIDISequence];
			MDPointerRelease(ptr);
			if (sts == kMDNoError) {

				/*  Update selection  */
				IntGroup *temp1 = IntGroupNew();
				IntGroup *temp2 = IntGroupNew();
				if (temp1 == NULL || temp2 == NULL)
					return NO;
				sts = IntGroupAdd(temp1, position, 1);
				if (sts == kMDNoError)
					sts = IntGroupNegate(temp1, temp2);
				if (sts == kMDNoError) {
					IntGroupClear(temp1);
					sts = IntGroupConvolute([(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet], temp2, temp1);
				}
				if (sts == kMDNoError)
					[self setSelection: [[[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: temp1] autorelease] inTrack: trackNo sender: self];
				IntGroupRelease(temp1);
				IntGroupRelease(temp2);

				/*  Register undo action for change of track duration (if necessary)  */
				[self registerUndoChangeTrackDuration: oduration ofTrack: trackNo];
				/*  Register undo action (delete)  */
				[[[self undoManager] prepareWithInvocationTarget: self]
					deleteEventAt: position fromTrack: trackNo];
				/*  Post the notification that any track has been modified  */
				[self enqueueTrackModifiedNotification: trackNo];
				return YES;
			}
		}
	}
	return NO;			
}

- (BOOL)deleteEventAt: (int32_t)position fromTrack: (int32_t)trackNo
{
	MDTrack *track;
	MDPointer *ptr;
	MDStatus sts;
	track = [[self myMIDISequence] getTrackAtIndex: trackNo];
	if (track != NULL) {
		ptr = MDPointerNew(track);
		if (ptr != NULL) {
			MDEventObject *eventObj = [[[MDEventObject allocWithZone:[self zone]] init] autorelease];
			[self lockMIDISequence];
			MDPointerSetPosition(ptr, position);
			eventObj->position = position;
            sts = MDPointerDeleteAnEvent(ptr, &eventObj->event);
			[self unlockMIDISequence];
			MDPointerRelease(ptr);
			if (sts == kMDNoError) {

				/*  Update selection  */
				IntGroup *temp1 = IntGroupNew();
				IntGroup *temp2 = IntGroupNew();
				if (temp1 == NULL || temp2 == NULL)
					return NO;
				sts = IntGroupAdd(temp1, position, 1);
				if (sts == kMDNoError)
					sts = IntGroupNegate(temp1, temp2);
				if (sts == kMDNoError) {
					IntGroupClear(temp1);
					sts = IntGroupDeconvolute([(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet], temp2, temp1);
				}
				if (sts == kMDNoError)
					[self setSelection: [[[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: temp1] autorelease] inTrack: trackNo sender: self];
				IntGroupRelease(temp1);
				IntGroupRelease(temp2);

				/*  Register undo action  */
				[[[self undoManager] prepareWithInvocationTarget: self]
					insertEvent: eventObj toTrack: trackNo];
				/*  Post the notification that any track has been modified  */
				[self enqueueTrackModifiedNotification: trackNo];
				return YES;
			}
		}
	}
	return NO;			
}

- (BOOL)replaceEvent: (MDEventObject *)eventObj inTrack: (int32_t)trackNo
{
	MDTrack *track;
	MDPointer *ptr;
	MDStatus sts;
	track = [[self myMIDISequence] getTrackAtIndex: trackNo];
	if (track != NULL) {
		ptr = MDPointerNew(track);
		if (ptr != NULL) {
			MDTickType oduration;
			MDEventObject *orgEventObj = [[[MDEventObject allocWithZone:[self zone]] init] autorelease];
			[self lockMIDISequence];
			MDPointerSetPosition(ptr, eventObj->position);
			oduration = MDTrackGetDuration(track);
            sts = MDPointerReplaceAnEvent(ptr, &eventObj->event, &orgEventObj->event);
			orgEventObj->position = MDPointerGetPosition(ptr);
			[self unlockMIDISequence];
			MDPointerRelease(ptr);
			if (sts == kMDNoError) {

				if (eventObj->position != orgEventObj->position) {
					/*  Update selection  */
					IntGroup *temp1 = IntGroupNew();
					IntGroup *temp2 = IntGroupNew();
					IntGroup *temp3 = IntGroupNew();
					if (temp1 == NULL || temp2 == NULL || temp3 == NULL)
						return NO;
					sts = IntGroupAdd(temp1, eventObj->position, 1);
					if (sts == kMDNoError)
						sts = IntGroupNegate(temp1, temp2);
					if (sts == kMDNoError) {
						IntGroupClear(temp1);
						sts = IntGroupDeconvolute([(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet], temp2, temp1);
					}
					IntGroupClear(temp2);
					sts = IntGroupAdd(temp2, orgEventObj->position, 1);
					if (sts == kMDNoError)
						sts = IntGroupNegate(temp2, temp3);
					if (sts == kMDNoError) {
						IntGroupClear(temp2);
						sts = IntGroupConvolute(temp1, temp3, temp2);
					}
					if (sts == kMDNoError)
						[self setSelection: [[[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: temp2] autorelease] inTrack: trackNo sender: self];
					IntGroupRelease(temp1);
					IntGroupRelease(temp2);
					IntGroupRelease(temp3);
				}

				/*  Register undo action for change of track duration (if necessary)  */
				[self registerUndoChangeTrackDuration: oduration ofTrack: trackNo];
				/*  Register undo action  */
				[[[self undoManager] prepareWithInvocationTarget: self]
					replaceEvent: orgEventObj inTrack: trackNo];
				/*  Post the notification that any track has been modified  */
				[self enqueueTrackModifiedNotification: trackNo];
				return YES;
			}
		}
	}
	return NO;			
}

- (BOOL)insertMultipleEvents: (MDTrackObject *)trackObj at: (IntGroupObject *)pointSet toTrack: (int32_t)trackNo selectInsertedEvents: (BOOL)flag insertedPositions: (IntGroup **)outPtr
{
	MDTrack *track;
	IntGroup *pset;
	MDStatus sts;
	MDTickType oduration;
	track = [[self myMIDISequence] getTrackAtIndex: trackNo];
	if (track == NULL || trackObj == nil || trackObj->track == NULL)
		return NO;
	oduration = MDTrackGetDuration(track);
    if (pointSet != nil)
        pset = [pointSet pointSet];
    else pset = NULL;
	[self lockMIDISequence];
	sts = MDTrackMerge(track, trackObj->track, &pset);
	[self unlockMIDISequence];
	if (sts == kMDErrorNoEvents)
		return NO;
	if (sts == kMDNoError) {
		if (outPtr != NULL)
			*outPtr = pset;
        /*  Update selection  */
		if (flag) {
			[self setSelection: [[[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: pset] autorelease] inTrack: trackNo sender: self];
		} else {
			IntGroup *temp = IntGroupNew();
			IntGroup *newSelection = IntGroupNew();
			if (temp == NULL || newSelection == NULL)
				return NO;
			sts = IntGroupNegate(pset, temp);
			if (sts == kMDNoError)
				sts = IntGroupConvolute([(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet], temp, newSelection);
			if (sts == kMDNoError)
				[self setSelection: [[[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: newSelection] autorelease] inTrack: trackNo sender: self];
		}
		
		/*  Register undo action for change of track duration (if necessary)  */
		pointSet = [[[IntGroupObject allocWithZone: [self zone]] initWithMDPointSet: pset] autorelease];
		[self registerUndoChangeTrackDuration: oduration ofTrack: trackNo];
		/*  Register undo action  */
		[[[self undoManager] prepareWithInvocationTarget: self]
		 deleteMultipleEventsAt: pointSet fromTrack: trackNo deletedEvents: NULL];
		/*  Post the notification that any track has been modified  */
		[self enqueueTrackModifiedNotification: trackNo];

		return YES;
	} else {
		if (outPtr != NULL)
			*outPtr = NULL;
		return NO;
	}
}

- (BOOL)deleteMultipleEventsAt: (IntGroupObject *)pointSet fromTrack: (int32_t)trackNo deletedEvents: (MDTrack **)outPtr
{
	MDTrack *track, *newTrack;
	MDTrackObject *trackObj;
    IntGroup *pset;
	MDStatus sts;
	MDTickType oduration;
	track = [[self myMIDISequence] getTrackAtIndex: trackNo];
    pset = [pointSet pointSet];
	if (track == NULL || pointSet == nil || pset == NULL)
		return NO;
	oduration = MDTrackGetDuration(track);
	[self lockMIDISequence];
	sts = MDTrackUnmerge(track, &newTrack, pset);
	[self unlockMIDISequence];
	if (sts == kMDErrorNoEvents)
		return NO;
	if (sts == kMDNoError) {
        /*  Update selection  */
		IntGroup *newSelection = IntGroupNew();
	/*	if (0) {
			IntGroup *temp = IntGroupNew();
			if (temp == NULL || newSelection == NULL)
				return NO;
			sts = IntGroupNegate(pset, temp);
			if (sts == kMDNoError)
				sts = IntGroupDeconvolute([(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet], temp, newSelection);
		} */
		if (sts == kMDNoError)
			[self setSelection: [[[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: newSelection] autorelease] inTrack: trackNo sender: self];
		trackObj = [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: newTrack] autorelease];
		/*  Register undo action for change of track duration (if necessary)  */
		[self registerUndoChangeTrackDuration: oduration ofTrack: trackNo];
		/*  Register undo action  */
		[[[self undoManager] prepareWithInvocationTarget: self]
		 insertMultipleEvents: trackObj at: pointSet toTrack: trackNo selectInsertedEvents: NO insertedPositions: NULL];
		/*  Post the notification that any track has been modified  */
		[self enqueueTrackModifiedNotification: trackNo];
		
		if (outPtr != NULL) {
			/*  Duplicate newTrack  */
			MDTrack *newTrack2 = MDTrackNewFromTrack(newTrack);
			*outPtr = newTrack2;
		}

		MDTrackRelease(newTrack);
		return YES;
	}
	return NO;
}

- (BOOL)duplicateMultipleEventsAt: (IntGroupObject *)pointSet ofTrack: (int32_t)trackNo selectInsertedEvents: (BOOL)flag
{
	MDTrack *track, *newTrack;
	MDTrackObject *newTrackObj;
	MDPointer *pt;
    IntGroup *pset;
	MDEvent *ep;
//	MDStatus sts;
	track = [[self myMIDISequence] getTrackAtIndex: trackNo];
    pset = [pointSet pointSet];
	if (track == NULL || pointSet == nil || pset == NULL)
		return NO;
	newTrack = MDTrackNew();
	if (newTrack == NULL)
		return NO;
	pt = MDPointerNew(track);
	if (pt == NULL)
		return NO;
	[self lockMIDISequence];
	while ((ep = MDPointerForwardWithPointSet(pt, pset, NULL)) != NULL) {
		if (MDTrackAppendEvents(newTrack, ep, 1) != 1)
			return NO;
	}
	[self unlockMIDISequence];
	MDPointerRelease(pt);
	newTrackObj = [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: newTrack] autorelease];
	return [self insertMultipleEvents: newTrackObj at: nil toTrack: trackNo selectInsertedEvents: flag insertedPositions: NULL];
}

static int
sInternalComparatorByTick(void *t, const void *a, const void *b)
{
	MDTickType ta = ((MDTickType *)t)[*((int32_t *)a)];
	MDTickType tb = ((MDTickType *)t)[*((int32_t *)b)];
	if (ta < tb)
		return -1;
	else if (ta == tb)
		return 0;
	else return 1;
}

static int
sInternalComparatorByPosition(void *t, const void *a, const void *b)
{
	int32_t ta = ((int32_t *)t)[*((int32_t *)a)];
	int32_t tb = ((int32_t *)t)[*((int32_t *)b)];
	if (ta < tb)
		return -1;
	else if (ta == tb)
		return 0;
	else return 1;
}

- (BOOL)modifyTick: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (int32_t)trackNo mode: (MyDocumentModifyMode)mode destinationPositions: (id)destPositions setSelection: (BOOL)setSelection
{
	MDTrack *track = [[self myMIDISequence] getTrackAtIndex: trackNo];
    if (track == NULL)
        return NO;
	/*  Call the class method version  */
    return [MyDocument modifyTick: theData ofMultipleEventsAt: pointSet forMDTrack: track inDocument: self mode: mode destinationPositions: destPositions setSelection: setSelection];
}

/*  Implemented as a class method, because in some cases it is necessary to perform this operation for non-document tracks. */
+ (BOOL)modifyTick: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (id)doc mode: (MyDocumentModifyMode)mode destinationPositions: (id)destPositions setSelection: (BOOL)setSelection
{
    MDTrack *tempTrack;
	int32_t trackNo;
    MDEvent *ep;
    IntGroup *pset, *destPset;
    MDSelectionObject *newDestPointSet;
    int32_t index, length;
    MDTickType dataValue;
    const MDTickType *dataPtr;
    float floatDataValue;
    const float *floatDataPtr;
    MDStatus status;
    unsigned int dataMode;
    MyDocumentModifyMode undoMode;
	NSMutableData *tempData, *undoData, *undoPositions;
	MDTickType *tempDataPtr, *undoDataPtr;
	int32_t *undoPositionsPtr;
	const int32_t *destPositionsPtr;
	MDTickType oldDuration;
	MDPointer *tempTrackPtr;

	if (doc != nil)
		trackNo = [[doc myMIDISequence] lookUpTrack: track];
	else trackNo = -1;

	oldDuration = MDTrackGetDuration(track);
    pset = [pointSet pointSet];
    if (pset == NULL)
        return NO;
    length = IntGroupGetCount(pset);
	if (destPositions == nil)
		destPositionsPtr = NULL;
	else destPositionsPtr = (const int32_t *)[destPositions bytes];

	/*  Prepare tick data  */
	dataPtr = NULL;
    if ([theData isKindOfClass: [NSNumber class]]) {
        dataMode = 0;
        if (mode == MyDocumentModifyMultiply) {
            floatDataValue = [theData floatValue];
        } else {
            dataValue = [theData intValue];
        }
    } else if ([theData isKindOfClass: [NSData class]]) {
        dataMode = 1;
        if (mode == MyDocumentModifyMultiply) {
            floatDataPtr = (const float *)[theData bytes];
        } else {
            dataPtr = (const MDTickType *)[theData bytes];
        }
    } else {
        dataMode = 2;
    }
	
	/*  Allocate temporary arrays  */
	tempData = [NSMutableData dataWithLength: sizeof(MDTickType) * length];
	tempDataPtr = (MDTickType *)[tempData mutableBytes];
    undoData = [NSMutableData dataWithLength: sizeof(MDTickType) * length];
    undoDataPtr = (MDTickType *)[undoData mutableBytes];
    undoMode = (mode == MyDocumentModifyAdd ? mode : MyDocumentModifySet);
	undoPositions = [NSMutableData dataWithLength: sizeof(int32_t) * length];
	undoPositionsPtr = (int32_t *)[undoPositions mutableBytes];
	
	/*  Move the target events to a separate track  */
    status = MDTrackUnmerge(track, &tempTrack, pset);
    if (status != kMDNoError)
        return NO;
	tempTrackPtr = MDPointerNew(tempTrack);
	if (tempTrackPtr == NULL)
		return NO;

	/*  Get new/old tick values to tempDataPtr[] and undoDataPtr[]  */
	{
		MDTickType prevValue, newValue, oldValue;
		prevValue = 0;
		index = 0;
		while ((ep = MDPointerForward(tempTrackPtr)) != NULL) {
			oldValue = MDGetTick(ep);
			if (mode == MyDocumentModifySet || mode == MyDocumentModifyAdd) {
				if (dataMode == 0)
					newValue = dataValue;
				else if (dataMode == 1)
					newValue = dataPtr[index];
				else newValue = [[theData objectAtIndex: index] intValue];
				if (mode == MyDocumentModifyAdd)
					newValue += oldValue;
			} else if (mode == MyDocumentModifyMultiply) {
				if (dataMode == 0)
					newValue = oldValue * floatDataValue;
				else if (dataMode == 1)
					newValue = oldValue * floatDataPtr[index];
				else newValue = oldValue * [[theData objectAtIndex: index] floatValue];
			}
			if (newValue < prevValue) {
				undoMode = MyDocumentModifySet;  //  Undo can be no longer accomplished by simply adding negative of theData
				newValue = prevValue;
			}
			tempDataPtr[index] = newValue;
			undoDataPtr[index] = oldValue;
			index++;
		}
	}

	/*  Get old positions (for undo) to undoPositionsPtr[]  */
	{
		int32_t i, pt, endPt;
		index = 0;
		for (i = 0; (pt = IntGroupGetStartPoint(pset, i)) >= 0; i++) {
			endPt = IntGroupGetEndPoint(pset, i);
			while (pt < endPt) {
				undoPositionsPtr[index++] = pt++;
			}
		}
	}
	
	/*  Sort events, tempDataPtr, undoDataPtr, undoPositionsPtr  */
	{
		int32_t *new2old;
		void *tempBuffer;
		
		/*  Allocate temporary storage  */
		new2old = (int32_t *)malloc(sizeof(int32_t) * length);
		if (new2old == NULL)
			return NO;
		tempBuffer = malloc(sizeof(MDEvent) * length);
		if (tempBuffer == NULL)
			return NO;
		memset(tempBuffer, 0, sizeof(MDEvent) * length);
		
		/*  Get sorted index  */
		for (index = 0; index < length; index++)
			new2old[index] = index;
		if (destPositionsPtr != NULL)
			qsort_r(new2old, length, sizeof(new2old[0]), (void *)destPositionsPtr, sInternalComparatorByPosition);
		else
			qsort_r(new2old, length, sizeof(new2old[0]), tempDataPtr, sInternalComparatorByTick);
		
		/*  Sort events  */
		MDPointerSetPosition(tempTrackPtr, -1);
		index = 0;
		while ((ep = MDPointerForward(tempTrackPtr)) != NULL) {
			MDSetTick(ep, tempDataPtr[index]);
			MDEventMove((MDEvent *)tempBuffer + index, ep, 1);
			index++;
		}
		MDPointerSetPosition(tempTrackPtr, -1);
		index = 0;
		while ((ep = MDPointerForward(tempTrackPtr)) != NULL) {
			MDEventMove(ep, (MDEvent *)tempBuffer + new2old[index], 1);
			index++;
		}
		MDTrackRecache(tempTrack, 0);
		
		/*  Sort undoDataPtr  */
		memmove(tempBuffer, undoDataPtr, sizeof(MDTickType) * length);
		for (index = 0; index < length; index++)
			undoDataPtr[index] = *((MDTickType *)tempBuffer + new2old[index]);
		
		/*  Sort undoPositionsPtr  */
		memmove(tempBuffer, undoPositionsPtr, sizeof(int32_t) * length);
		for (index = 0; index < length; index++)
			undoPositionsPtr[index] = *((int32_t *)tempBuffer + new2old[index]);
			
		free(new2old);
		free(tempBuffer);
	}
	
	/*  Prepare destPset  */
	if (destPositionsPtr == NULL)
		destPset = NULL;
	else {
		destPset = IntGroupNew();
		for (index = 0; index < length; index++)
			IntGroupAdd(destPset, destPositionsPtr[index], 1);
	}

	/*  Merge the modified events back to the target track  */
	if (doc != nil)
		[doc lockMIDISequence];
    status = MDTrackMerge(track, tempTrack, &destPset);
	if (doc != nil)
		[doc unlockMIDISequence];
    if (status != kMDNoError)
        return NO;

	MDPointerRelease(tempTrackPtr);
	MDTrackRelease(tempTrack);
	
	if (doc != nil) {
        newDestPointSet = [[[MDSelectionObject allocWithZone: [doc zone]] initWithMDPointSet: destPset] autorelease];

        /*  Set selection  */
        if (setSelection) {
            [doc setSelection: newDestPointSet inTrack: trackNo sender: doc];
        }

		/*  Register undo action  */
		if (oldDuration != MDTrackGetDuration(track)) {
			[[[doc undoManager] prepareWithInvocationTarget: doc]
				changeTrackDuration: oldDuration ofTrack: trackNo];
		}
		[[[doc undoManager] prepareWithInvocationTarget: doc]
			modifyTick: 
				(undoMode == MyDocumentModifyAdd
					? (id)[NSNumber numberWithLong: -dataValue]
					: (id)undoData)
			ofMultipleEventsAt: newDestPointSet inTrack: trackNo mode: undoMode
            destinationPositions: undoPositions setSelection: setSelection];

		/*  Post the notification that this track has been modified  */
		[doc enqueueTrackModifiedNotification: trackNo];
	}
	
	IntGroupRelease(destPset);

    return YES;
}

- (BOOL)modifyCodes: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (int32_t)trackNo mode: (MyDocumentModifyMode)mode
{
	MDTrack *track = [[self myMIDISequence] getTrackAtIndex: trackNo];
    if (track == NULL)
        return NO;
	/*  Call the class method version  */
	return [MyDocument modifyCodes: theData ofMultipleEventsAt: pointSet forMDTrack: track inDocument: self mode: mode];
}

+ (BOOL)modifyCodes: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (MyDocument *)doc mode: (MyDocumentModifyMode)mode
{
	int32_t trackNo;
    MDPointer *ptr;
    MDEvent *ep;
    IntGroup *pset;
    int32_t index, length;
	int psetIndex;
    short dataValue, oldValue, newValue;
    short *dataPtr;
    float floatDataValue;
    float *floatDataPtr;
    unsigned int dataMode;
    MyDocumentModifyMode undoMode;
    NSMutableData *undoData;
    short *undoDataPtr;
	if (doc != nil)
		trackNo = [[doc myMIDISequence] lookUpTrack: track];
	else trackNo = -1;
    ptr = MDPointerNew(track);
    if (ptr == NULL)
        return NO;
    pset = [pointSet pointSet];
    if (pset == NULL)
        return NO;
    length = IntGroupGetCount(pset);
    if ([theData isKindOfClass: [NSNumber class]]) {
        dataMode = 0;
        if (mode == MyDocumentModifyMultiply) {
            floatDataValue = [theData floatValue];
        } else {
            dataValue = [theData intValue];
        }
    } else if ([theData isKindOfClass: [NSData class]]) {
        dataMode = 1;
        if (mode == MyDocumentModifyMultiply) {
            floatDataPtr = (float *)[theData bytes];
        } else {
            dataPtr = (short *)[theData bytes];
        }
    } else {
        dataMode = 2;
    }
    undoData = [NSMutableData dataWithLength: sizeof(short) * length];
    undoDataPtr = (short *)[undoData mutableBytes];
    undoMode = (mode == MyDocumentModifyAdd ? mode : MyDocumentModifySet);
    index = 0;
    MDPointerSetPositionWithPointSet(ptr, pset, -1, &psetIndex);
	if (doc != nil)
		[doc lockMIDISequence];
    while ((ep = MDPointerForwardWithPointSet(ptr, pset, &psetIndex)) != NULL) {
    //    if (MDGetKind(ep) != kMDEventNote)
    //        continue;
        oldValue = MDGetCode(ep);
        if (mode == MyDocumentModifySet || mode == MyDocumentModifyAdd) {
            if (dataMode == 0)
                newValue = dataValue;
            else if (dataMode == 1)
                newValue = dataPtr[index];
            else newValue = [[theData objectAtIndex: index] intValue];
            if (mode == MyDocumentModifyAdd)
                newValue += oldValue;
        } else if (mode == MyDocumentModifyMultiply) {
            if (dataMode == 0)
                newValue = oldValue * floatDataValue;
            else if (dataMode == 1)
                newValue = oldValue * floatDataPtr[index];
            else newValue = oldValue * [[theData objectAtIndex: index] floatValue];
        }
        if (newValue < 0 || newValue > 127) {
            undoMode = MyDocumentModifySet;  //  Undo can be no longer accomplished by simply adding negative of theData
            if (newValue < 0)
                newValue = 0;
            else newValue = 127;
        }
        MDSetCode(ep, newValue);
        undoDataPtr[index] = oldValue;
        index++;
    }
	if (doc != nil)
		[doc unlockMIDISequence];
//    fprintf(stderr, "modifyCodes: undoMode=%d undoData=(", (int)undoMode);
//    { int i; for (i = 0; i < [undoData length] / 2; i++) fprintf(stderr, "%s%d", (i!=0?",":""), ((short *)[undoData bytes])[i]); }
//    fprintf(stderr, ")\n");
	if (doc != nil) {
		/*  Register undo action  */
		[[[doc undoManager] prepareWithInvocationTarget: doc]
			modifyCodes: 
				(undoMode == MyDocumentModifyAdd
					? (id)[NSNumber numberWithInt: -dataValue]
					: (id)undoData)
			ofMultipleEventsAt: pointSet inTrack: trackNo mode: undoMode];
		/*  Post the notification that this track has been modified  */
		[doc enqueueTrackModifiedNotification: trackNo];
	}
    return YES;
}

- (BOOL)modifyDurations: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (int32_t)trackNo mode: (MyDocumentModifyMode)mode
{
	MDTrack *track = [[self myMIDISequence] getTrackAtIndex: trackNo];
    if (track == NULL)
        return NO;
	/*  Call the class method version  */
	return [MyDocument modifyDurations: theData ofMultipleEventsAt: pointSet forMDTrack: track inDocument: self mode: mode];
}

+ (BOOL)modifyDurations: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (MyDocument *)doc mode: (MyDocumentModifyMode)mode
{
	int32_t trackNo;
    MDPointer *ptr;
    MDEvent *ep;
    IntGroup *pset;
    int32_t index, length;
	int psetIndex;
    MDTickType dataValue, oldValue, newValue;
    MDTickType *dataPtr;
    MDTickType maxTick;
    float floatDataValue;
    float *floatDataPtr;
    unsigned int dataMode;
    MyDocumentModifyMode undoMode;
    NSMutableData *undoData;
    MDTickType *undoDataPtr;
	MDTickType oldDuration;
	
	if (doc != nil)
		trackNo = [[doc myMIDISequence] lookUpTrack: track];
	else trackNo = -1;
	oldDuration = MDTrackGetDuration(track);
    ptr = MDPointerNew(track);
    if (ptr == NULL)
        return NO;
    pset = [pointSet pointSet];
    if (pset == NULL)
        return NO;
    length = IntGroupGetCount(pset);
    if ([theData isKindOfClass: [NSNumber class]]) {
        dataMode = 0;
        if (mode == MyDocumentModifyMultiply) {
            floatDataValue = [theData floatValue];
        } else {
            dataValue = [theData intValue];
        }
    } else if ([theData isKindOfClass: [NSData class]]) {
        dataMode = 1;
        if (mode == MyDocumentModifyMultiply) {
            floatDataPtr = (float *)[theData bytes];
        } else {
            dataPtr = (MDTickType *)[theData bytes];
        }
    } else {
        dataMode = 2;
    }
    undoData = [NSMutableData dataWithLength: sizeof(MDTickType) * length];
    undoDataPtr = (MDTickType *)[undoData mutableBytes];
    undoMode = (mode == MyDocumentModifyAdd ? mode : MyDocumentModifySet);
    index = 0;
    MDPointerSetPositionWithPointSet(ptr, pset, -1, &psetIndex);
    maxTick = -1;
	if (doc != nil)
		[doc lockMIDISequence];
    while ((ep = MDPointerForwardWithPointSet(ptr, pset, &psetIndex)) != NULL) {
        if (MDGetKind(ep) != kMDEventNote)
            continue;
        oldValue = MDGetDuration(ep);
        if (mode == MyDocumentModifySet || mode == MyDocumentModifyAdd) {
            if (dataMode == 0)
                newValue = dataValue;
            else if (dataMode == 1)
                newValue = dataPtr[index];
            else newValue = [[theData objectAtIndex: index] intValue];
            if (mode == MyDocumentModifyAdd)
                newValue += oldValue;
        } else if (mode == MyDocumentModifyMultiply) {
            if (dataMode == 0)
                newValue = oldValue * floatDataValue;
            else if (dataMode == 1)
                newValue = oldValue * floatDataPtr[index];
            else newValue = oldValue * [[theData objectAtIndex: index] floatValue];
        }
        if (newValue <= 0 || newValue > kMDMaxTick / 2) {
            undoMode = MyDocumentModifySet;  //  Undo can be no longer accomplished by simply adding negative of theData
            if (newValue <= 0)
                newValue = 1;
            else newValue = kMDMaxTick / 2;
        }
		MDPointerSetDuration(ptr, newValue);
        if (MDGetTick(ep) + newValue > maxTick)
            maxTick = MDGetTick(ep) + newValue;
        undoDataPtr[index] = oldValue;
        index++;
    }
    if (maxTick >= MDTrackGetDuration(track)) {
		if (doc != nil)
			[doc changeTrackDuration: maxTick + 1 ofTrack: trackNo];
		else
			MDTrackSetDuration(track, maxTick + 1);
    }
	if (doc != nil)
		[doc unlockMIDISequence];
//    fprintf(stderr, "modifyCodes: undoMode=%d undoData=(", (int)undoMode);
//    { int i; for (i = 0; i < [undoData length] / 2; i++) fprintf(stderr, "%s%d", (i!=0?",":""), ((short *)[undoData bytes])[i]); }
//    fprintf(stderr, ")\n");
    /*  Register undo action  */
	if (doc != nil) {
		if (oldDuration != MDTrackGetDuration(track)) {
			[[[doc undoManager] prepareWithInvocationTarget: doc]
				changeTrackDuration: oldDuration ofTrack: trackNo];
		}
		[[[doc undoManager] prepareWithInvocationTarget: doc]
			modifyDurations: 
				(undoMode == MyDocumentModifyAdd
					? (id)[NSNumber numberWithLong: -dataValue]
					: (id)undoData)
			ofMultipleEventsAt: pointSet inTrack: trackNo mode: undoMode];
		/*  Post the notification that this track has been modified  */
		[doc enqueueTrackModifiedNotification: trackNo];
	}
    return YES;
}

- (BOOL)modifyData: (id)theData forEventKind: (unsigned char)eventKind ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (int32_t)trackNo mode: (MyDocumentModifyMode)mode
{
	MDTrack *track = [[self myMIDISequence] getTrackAtIndex: trackNo];
    if (track == NULL)
        return NO;
	/*  Call the class method version  */
	return [MyDocument modifyData: theData forEventKind: eventKind ofMultipleEventsAt: pointSet forMDTrack: track inDocument: self mode: mode];
}

+ (BOOL)modifyData: (id)theData forEventKind: (unsigned char)eventKind ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (MyDocument *)doc mode: (MyDocumentModifyMode)mode
{
	int32_t trackNo;
    MDPointer *ptr;
    MDEvent *ep;
    IntGroup *pset;
    int32_t index, length;
	int psetIndex;
    float dataValue, oldValue, newValue;
    float dataMin, dataMax;
    short *dataPtr;
    float *floatDataPtr;
    unsigned int dataMode;
    MyDocumentModifyMode undoMode;
    NSMutableData *undoData;
    short *undoDataPtr;
    float *floatUndoDataPtr;
	BOOL floatFlag;
	if (doc != nil)
		trackNo = [[doc myMIDISequence] lookUpTrack: track];
	else trackNo = -1;
    ptr = MDPointerNew(track);
    if (ptr == NULL)
        return NO;
    pset = [pointSet pointSet];
    if (pset == NULL)
        return NO;
    length = IntGroupGetCount(pset);
    if ([theData isKindOfClass: [NSNumber class]]) {
        dataMode = 0;
        dataValue = [theData floatValue];
    } else if ([theData isKindOfClass: [NSData class]]) {
        dataMode = 1;
        if ([theData length] >= length * sizeof(float)) {
            floatDataPtr = (float *)[theData bytes];
			floatFlag = YES;
        } else {
            dataPtr = (short *)[theData bytes];
			floatFlag = NO;
        }
    } else {
        dataMode = 2;
    }
    if (eventKind == kMDEventPitchBend) {
        dataMax = 8191;
        dataMin = -8192;
    } else if (eventKind == kMDEventTempo) {
        dataMax = kMDMaxTempo;
        dataMin = kMDMinTempo;
    } else {
        dataMax = 127;
        dataMin = 0;
    }
    if (eventKind == kMDEventTempo) {
        undoData = [NSMutableData dataWithLength: sizeof(float) * length];
        floatUndoDataPtr = (float *)[undoData mutableBytes];
    } else {
        undoData = [NSMutableData dataWithLength: sizeof(short) * length];
        undoDataPtr = (short *)[undoData mutableBytes];
    }
    if (mode == MyDocumentModifyAdd && eventKind != kMDEventTempo)
        undoMode = MyDocumentModifyAdd;
    else undoMode = MyDocumentModifySet;
    index = 0;
    MDPointerSetPositionWithPointSet(ptr, pset, -1, &psetIndex);
	if (doc != nil)
		[doc lockMIDISequence];
    while ((ep = MDPointerForwardWithPointSet(ptr, pset, &psetIndex)) != NULL) {
        if (MDGetKind(ep) != eventKind
        && (eventKind != kMDEventInternalNoteOff || MDGetKind(ep) != kMDEventNote))
            continue;
		if (eventKind == kMDEventNote)
			oldValue = MDGetNoteOnVelocity(ep);
        else if (eventKind == kMDEventInternalNoteOff)
            oldValue = MDGetNoteOffVelocity(ep);
        else if (eventKind == kMDEventTempo)
            oldValue = MDGetTempo(ep);
        else oldValue = MDGetData1(ep);
        if (mode == MyDocumentModifySet || mode == MyDocumentModifyAdd) {
            if (dataMode == 0)
                newValue = dataValue;
            else if (dataMode == 1)
                newValue = (floatFlag ? floatDataPtr[index] : (float)dataPtr[index]);
            else newValue = [[theData objectAtIndex: index] floatValue];
            if (mode == MyDocumentModifyAdd) {
                newValue += oldValue;
            }
        } else if (mode == MyDocumentModifyMultiply) {
            float multiple;
            if (dataMode == 0)
                multiple = dataValue;
            else if (dataMode == 1)
                multiple = (floatFlag ? floatDataPtr[index] : (float)dataPtr[index]);
            else multiple = [[theData objectAtIndex: index] floatValue];
            newValue = oldValue * multiple;
        }
        if (newValue < dataMin || newValue > dataMax) {
            undoMode = MyDocumentModifySet;  //  Undo can be no longer accomplished by simply adding negative of theData
            if (newValue < dataMin)
                newValue = dataMin;
            else newValue = dataMax;
        }
        if (eventKind == kMDEventNote)
            MDSetNoteOnVelocity(ep, newValue);
        else if (eventKind == kMDEventInternalNoteOff)
            MDSetNoteOffVelocity(ep, newValue);
        else if (eventKind == kMDEventTempo)
            MDSetTempo(ep, newValue);
        else MDSetData1(ep, newValue);
        if (eventKind == kMDEventTempo)
            floatUndoDataPtr[index] = oldValue;
        else undoDataPtr[index] = oldValue;
        index++;
    }
	if (doc != nil)
		[doc unlockMIDISequence];
//    fprintf(stderr, "modifyCodes: undoMode=%d undoData=(", (int)undoMode);
//    { int i; for (i = 0; i < [undoData length] / 2; i++) fprintf(stderr, "%s%d", (i!=0?",":""), ((short *)[undoData bytes])[i]); }
//    fprintf(stderr, ")\n");
	if (doc != nil) {
		/*  Register undo action  */
		[[[doc undoManager] prepareWithInvocationTarget: doc]
			modifyData: 
				(undoMode == MyDocumentModifyAdd
					? (id)[NSNumber numberWithFloat: -dataValue]
					: (id)undoData)
			forEventKind: eventKind
			ofMultipleEventsAt: pointSet inTrack: trackNo mode: undoMode];
		/*  Post the notification that this track has been modified  */
		[doc enqueueTrackModifiedNotification: trackNo];
	}
    return YES;
}

- (const MDEvent *)eventAtPosition: (int32_t)position inTrack: (int32_t)trackNo
{
	MDTrack *track;
	MDEvent *ep1;
	MDPointer *pt1;
	track = MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo);
	pt1 = MDPointerNew(track);
	if (pt1 != NULL && MDPointerSetPosition(pt1, position)) {
		ep1 = MDPointerCurrent(pt1);
	} else ep1 = NULL;
	MDPointerRelease(pt1);
	return ep1;
}

- (int32_t)changeTick: (int32_t)tick atPosition: (int32_t)position inTrack: (int32_t)trackNo originalPosition: (int32_t)pos1
{
	MDTrack *track;
	MDEvent *ep1;
	MDPointer *pt1;
	int32_t opos1, npos;
	MDTickType otick, oduration, duration;
	MDStatus sts = kMDNoError;
	track = MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo);
	pt1 = MDPointerNew(track);
	if (pt1 != NULL && MDPointerSetPosition(pt1, position) && (ep1 = MDPointerCurrent(pt1)) != NULL) {
		otick = MDGetTick(ep1);
		if (otick == tick)
			return -1;	/*  Do nothing  */
		opos1 = MDPointerGetPosition(pt1);
		oduration = MDTrackGetDuration(track);
		[self lockMIDISequence];
		if (otick < tick) {
			/*  Move pt2 first, then ep1  */
			if (sts == kMDNoError)
				sts = MDPointerChangeTick(pt1, tick, pos1);
		} else {
			/*  Move pt1 first, then ep2  */
			sts = MDPointerChangeTick(pt1, tick, pos1);
		}
		[self unlockMIDISequence];
		if (sts == kMDNoError) {
			/*  The position of the event after moving  */
			npos = MDPointerGetPosition(pt1);
			/*  Register undo action with the current values  */
			duration = MDTrackGetDuration(track);
			if (oduration != duration)
				[[[self undoManager] prepareWithInvocationTarget: self]
					changeTrackDuration: oduration ofTrack: trackNo];
			[[[self undoManager] prepareWithInvocationTarget: self]
				changeTick: otick atPosition: npos inTrack: trackNo originalPosition: opos1];
			/*  Post the notification that any track has been modified  */
			[self enqueueTrackModifiedNotification: trackNo];
        } else npos = -1;
		MDPointerRelease(pt1);
		return npos;
	}
	if (pt1 != NULL)
		MDPointerRelease(pt1);
	return -1;
}

- (BOOL)changeChannel: (int)channel atPosition: (int32_t)position inTrack: (int32_t)trackNo
{
	MDEvent *ep;
	int ch;
	MDPointer *pointer = MDPointerNew(MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo));
	if (pointer != NULL && MDPointerSetPosition(pointer, position) && (ep = MDPointerCurrent(pointer)) != NULL) {
		if (MDIsChannelEvent(ep)) {
			ch = MDGetChannel(ep);
			MDSetChannel(ep, (channel & 15));
			if (ch != channel) {
				/*  Register undo action with current value  */
				[[[self undoManager] prepareWithInvocationTarget: self]
					changeChannel: ch atPosition: position inTrack: trackNo];
				/*  Post the notification that any track has been modified  */
				[self enqueueTrackModifiedNotification: trackNo];
				MDPointerRelease(pointer);
				return YES;
			}
		}
	}
	if (pointer != NULL)
		MDPointerRelease(pointer);
	return NO;
}

- (BOOL)changeDuration: (int32_t)duration atPosition: (int32_t)position inTrack: (int32_t)trackNo
{
	MDTrack *track;
	MDEvent *ep1;
	MDPointer *pt1;
	int32_t oduration, oldTrackDuration;
	BOOL modified = NO;
	track = MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo);
	pt1 = MDPointerNew(track);
	oldTrackDuration = MDTrackGetDuration(track);
	if (pt1 != NULL && MDPointerSetPosition(pt1, position) && (ep1 = MDPointerCurrent(pt1)) != NULL) {
		if (MDGetKind(ep1) == kMDEventNote) {
			oduration = MDGetDuration(ep1);
			if (oduration != duration) {
				[self lockMIDISequence];
				if (MDGetTick(ep1) + duration >= oldTrackDuration) {
					MDTickType newTrackDuration = MDGetTick(ep1) + duration + 1;
					[self changeTrackDuration: newTrackDuration ofTrack: trackNo];
				}
				MDPointerSetDuration(pt1, duration);
				[self unlockMIDISequence];
				/*  Register undo action for change of track duration (if necessary)  */
				[self registerUndoChangeTrackDuration: oldTrackDuration ofTrack: trackNo];
				/*  Register undo action with current value  */
				[[[self undoManager] prepareWithInvocationTarget: self]
					changeDuration: oduration atPosition: position inTrack: trackNo];
				/*  Post the notification that any track has been modified  */
				[self enqueueTrackModifiedNotification: trackNo];
				modified = YES;
			}
		}
	}
	return modified;
}

- (BOOL)changeValue: (MDEventFieldDataWhole)wholeValue ofType: (int)code atPosition: (int32_t)position inTrack: (int32_t)trackNo
{
	MDEventFieldData ed1, ed2, value;
	MDEvent *ep;
	int d1, d2;
	MDPointer *pointer = MDPointerNew(MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo));

	value.whole = wholeValue;
	ed1 = ed2 = value;

	if (pointer != NULL && MDPointerSetPosition(pointer, position) && (ep = MDPointerCurrent(pointer)) != NULL) {
		[self lockMIDISequence];
		switch (code) {
			case kMDEventFieldKindAndCode:
				/*  Kind should be the same with the original  */
				if (MDGetKind(ep) == ed1.ucValue[0]) {
					ed2.ucValue[1] = MDGetCode(ep);
					MDSetCode(ep, ed1.ucValue[1]);
				} else if (ed1.ucValue[0] == kMDEventNote && (MDGetKind(ep) == kMDEventNote)) {
					ed2.ucValue[1] = MDGetCode(ep);
					MDSetCode(ep, ed1.ucValue[1]);
				}
				break;
			case kMDEventFieldVelocities:
			{
				d1 = ed1.ucValue[0];
				d2 = ed1.ucValue[1];
				if (d1 == 0)
					d1 = 1;
				switch (MDGetKind(ep)) {
					case kMDEventNote:
					/*	ed2.ucValue[0] = ((MDGetData1(ep) >> 8) & 0xff);
						ed2.ucValue[1] = (MDGetData1(ep) & 0xff);
						MDSetData1(ep, ((d1 & 0xff) << 8) + (d2 & 0xff)); */
						ed2.ucValue[0] = MDGetNoteOnVelocity(ep);
						ed2.ucValue[1] = MDGetNoteOffVelocity(ep);
						MDSetNoteOnVelocity(ep, d1);
						MDSetNoteOffVelocity(ep, d2);
						break;
				}
				break;
			}
			case kMDEventFieldData:
				ed2.intValue = MDGetData1(ep);
				MDSetData1(ep, ed1.intValue);
				break;
			case kMDEventFieldSMPTE:
			{
				MDSMPTERecord *smp;
				smp = MDGetSMPTERecordPtr(ep);
				ed2.smpte = *smp;
				*smp = ed1.smpte;
				break;
			}
			case kMDEventFieldMetaData:
			{
				unsigned char *ptr;
				ptr = MDGetMetaDataPtr(ep);
				memcpy(ed2.ucValue, ptr, 4);
				memcpy(ptr, ed1.ucValue, 4);
				break;
			}
			case kMDEventFieldTempo:
            {
                float tempo;
				ed2.floatValue = MDGetTempo(ep);
                tempo = ed1.floatValue;
                if (tempo < kMDMinTempo)
                    tempo = kMDMinTempo;
                else if (tempo > kMDMaxTempo)
                    tempo = kMDMaxTempo;
				MDSetTempo(ep, ed1.floatValue);
				break;
            }
		}
		[self unlockMIDISequence];
	}
	if (pointer != NULL)
		MDPointerRelease(pointer);
	
	if (ed1.whole != ed2.whole) {
		/*  Register undo action with current value  */
			[[[self undoManager] prepareWithInvocationTarget: self]
				changeValue: ed2.whole ofType: code atPosition: position inTrack: trackNo];
		/*  Post the notification that any track has been modified  */
			[self enqueueTrackModifiedNotification: trackNo];
		return YES;
	} else return NO;
}

- (BOOL)changeMessage: (NSData *)data atPosition: (int32_t)position inTrack: (int32_t)trackNo
{
	MDEvent *ep;
	MDPointer *pointer = MDPointerNew(MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo));
	NSData *data2 = nil;
	BOOL modify = NO;

	if (pointer != NULL && MDPointerSetPosition(pointer, position) && (ep = MDPointerCurrent(pointer)) != NULL) {
		if (MDHasEventMessage(ep)) {
			const unsigned char *ptr;
			int32_t length;
			[self lockMIDISequence];
			ptr = MDGetMessageConstPtr(ep, &length);
			data2 = [NSData dataWithBytes: ptr length: length];
			/*  Will the data really need modification?  */
			if (MDIsTextMetaEvent(ep)) {
				if (length != [data length] || strncmp((char *)[data bytes], (char *)[data2 bytes], length) != 0)
					modify = YES;
			} else {
				if (![data isEqualToData: data2])
					modify = YES;
			}
			if (modify) {
				length = (int)[data length];
				if (MDSetMessageLength(ep, length) == length)
					MDSetMessage(ep, [data bytes]);
			}
			[self unlockMIDISequence];
		}
	}
	if (pointer != NULL)
		MDPointerRelease(pointer);
	
	if (modify) {
		/*  Register undo action with current value  */
		[[[self undoManager] prepareWithInvocationTarget: self]
			changeMessage: data2 atPosition: position inTrack: trackNo];
		/*  Post the notification that any track has been modified  */
		[self enqueueTrackModifiedNotification: trackNo];
		return YES;
	} else return NO;
}

/*
- (BOOL)changeDeviceNumber: (int32_t)deviceNumber forTrack: (int32_t)trackNo;
{
	int32_t oldNumber;
	MDTrack *track = [myMIDISequence getTrackAtIndex: trackNo];
	if (track != NULL) {
        oldNumber = MDTrackGetDevice(track);
        if (oldNumber == deviceNumber)
            return NO;	//  No need to change
		MDTrackSetDevice(track, deviceNumber);
        [[[self undoManager] prepareWithInvocationTarget: self]
            changeDeviceNumber: oldNumber forTrack: trackNo];
		[self enqueueTrackModifiedNotification: trackNo];
        [self updateTrackDestinations];
        return YES;
	}
	return NO;
}
*/

#pragma mark ====== Editing range ======

//- (void)setNeedsUpdateEditingRange: (BOOL)flag
//{
//	needsUpdateEditingRange = YES;
//}

- (void)getEditingRangeStart: (MDTickType *)startTick end: (MDTickType *)endTick
{
//	if (needsUpdateEditingRange)
//		[self updateEditingRange];
	*startTick = startEditingRange;
	*endTick = endEditingRange;
}

- (void)setEditingRangeStart: (MDTickType)startTick end: (MDTickType)endTick
{
	if (startTick < 0 && endTick < 0) {
		startTick = endTick = kMDNegativeTick;
	} else if (startTick >= 0 && endTick >= startTick) {
	/*	MDTickType maxTick = [[self myMIDISequence] sequenceDuration];
		if (endTick >= maxTick)
			endTick = maxTick;
		if (startTick >= maxTick)
			startTick = maxTick; */
	} else return;
	[self enqueueSelectionUndoerWithKey: sEditingRangeKey value: [[[MDTickRangeObject alloc] initWithStartTick: startEditingRange endTick: endEditingRange] autorelease]];
	startEditingRange = startTick;
	endEditingRange = endTick;
//	needsUpdateEditingRange = NO;
//	[self postEditingRangeDidChangeNotification];
}

#pragma mark ====== Selection ======

/*  NOTE: setSelection and toggleSelection are the main methods to modify track selections.
    Other methods calls these main methods with appropriate parameters.  */

- (BOOL)setSelection: (MDSelectionObject *)set inTrack: (int32_t)trackNo sender: (id)sender
{
/*    MDSelectionObject *diffSet = [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease]; */
    MDSelectionObject *oldSet = (MDSelectionObject *)[[[selections objectAtIndex: trackNo] retain] autorelease];

	[selections replaceObjectAtIndex: trackNo withObject: set];
	[self enqueueSelectionUndoerWithKey: [NSNumber numberWithInt: (int)trackNo] value: oldSet];
	return YES;
/*    MDStatus sts = IntGroupXor([oldSet pointSet], [set pointSet], [diffSet pointSet]);
    if (sts == kMDNoError) {
        [selections replaceObjectAtIndex: trackNo withObject: set];
#if DEBUG
        if (gMDVerbose > 0)
            IntGroupDump([set pointSet]);
#endif
		[self setNeedsUpdateEditingRange: YES];
        [self postSelectionDidChangeNotification: trackNo selectionChange: diffSet sender: sender];
		[self postEditingRangeDidChangeNotification];
        return YES;
    } else return NO; */
}

- (BOOL)toggleSelection: (MDSelectionObject *)pointSet inTrack: (int32_t)trackNo sender: (id)sender
{
    MDSelectionObject *newSet = [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease];
    MDSelectionObject *oldSet = (MDSelectionObject *)[[[selections objectAtIndex: trackNo] retain] autorelease];
    MDStatus sts = IntGroupXor([oldSet pointSet], [pointSet pointSet], [newSet pointSet]);
    if (sts == kMDNoError) {
        /*  Register undo action  */
   /*     [[[self undoManager] prepareWithInvocationTarget: self]
            toggleSelection: pointSet inTrack: trackNo sender: self]; */
        /*  Do set selection  */
        [selections replaceObjectAtIndex: trackNo withObject: newSet];
        /*  For debug  */
#if DEBUG
        if (gMDVerbose > 0)
            IntGroupDump([newSet pointSet]);
#endif
		[self enqueueSelectionUndoerWithKey: [NSNumber numberWithInt: (int)trackNo] value: oldSet];

		/*  Update editing range  */
	//	[self setNeedsUpdateEditingRange: YES];
        /*  Post notification  */
    //  [self postSelectionDidChangeNotification: trackNo selectionChange: pointSet sender: sender];
	//	[self postEditingRangeDidChangeNotification];
        return YES;
    } else return NO;
}

- (BOOL)selectEventAtPosition: (int32_t)position inTrack: (int32_t)trackNo sender: (id)sender
{
    if (!IntGroupLookup([(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet], position, NULL)) {
        MDSelectionObject *pointSet = [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease];
        IntGroupAdd([pointSet pointSet], position, 1);
        [self toggleSelection: pointSet inTrack: trackNo sender: sender];
        return YES;
    } else return NO;
}

- (BOOL)unselectEventAtPosition: (int32_t)position inTrack: (int32_t)trackNo sender: (id)sender
{
    if (IntGroupLookup([(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet], position, NULL)) {
        MDSelectionObject *pointSet = [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease];
        IntGroupAdd([pointSet pointSet], position, 1);
        [self toggleSelection: pointSet inTrack: trackNo sender: sender];
        return YES;
    } else return NO;
}

- (BOOL)selectAllEventsInTrack: (int32_t)trackNo sender: (id)sender
{
    MDStatus sts;
    MDSelectionObject *pointSet = [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease];
    sts = IntGroupAdd([pointSet pointSet], 0, MDTrackGetNumberOfEvents([[self myMIDISequence] getTrackAtIndex: trackNo]));
    if (sts == kMDNoError) {
        return [self setSelection: pointSet inTrack: trackNo sender: sender];
    } else return NO;
}

- (BOOL)unselectAllEventsInTrack: (int32_t)trackNo sender: (id)sender
{
	MDSelectionObject *sel;
	sel = [self selectionOfTrack: trackNo];
	if (sel != nil && (IntGroupGetIntervalCount([sel pointSet]) > 0 || sel->isEndOfTrackSelected)) {
		sel = [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease];
		return [self setSelection: sel inTrack: trackNo sender: sender];
	} else return NO;  /* No need to change */
}

- (BOOL)unselectAllEventsInAllTracks: (id)sender
{
	int i;
	for (i = [[self myMIDISequence] trackCount] - 1; i >= 0; i--) {
		[self unselectAllEventsInTrack: i sender: sender];
	}
	return YES;
}

- (BOOL)addSelection: (IntGroupObject *)set inTrack: (int32_t)trackNo sender: (id)sender
{
    MDSelectionObject *pointSet = [[[MDSelectionObject allocWithZone: [self zone]] init] autorelease];
    MDSelectionObject *oldSet = (MDSelectionObject *)[selections objectAtIndex: trackNo];
    MDStatus sts = IntGroupUnion([oldSet pointSet], [set pointSet], [pointSet pointSet]);
    if (sts == kMDNoError)
        return [self setSelection: pointSet inTrack: trackNo sender: sender];
    else return NO;
}

- (BOOL)isSelectedAtPosition: (int32_t)position inTrack: (int32_t)trackNo
{
    IntGroup *selection;
    selection = [(MDSelectionObject *)[selections objectAtIndex: trackNo] pointSet];
    if (selection != NULL) {
        return (IntGroupLookup(selection, position, NULL) != 0);
    } else return NO;
}

- (MDSelectionObject *)selectionOfTrack: (int32_t)trackNo
{
    return [[(MDSelectionObject *)[selections objectAtIndex: trackNo] retain] autorelease];
}

- (MDSelectionObject *)eventSetInTrack: (int32_t)trackNo eventKind: (int)eventKind eventCode: (int)eventCode fromTick: (MDTickType)fromTick toTick: (MDTickType)toTick fromData: (float)fromData toData: (float)toData inPointSet: (IntGroupObject *)pointSet
{
	MDEvent *ep;
	MDPointer *pointer = MDPointerNew(MDSequenceGetTrack([[self myMIDISequence] mySequence], trackNo));
	IntGroup *pset;
	IntGroup *resultSet;
	MDSelectionObject *retObj;
	int psetIndex;
	int32_t pos;
	int i;

	if (pointer == NULL)
		return nil;

	//  Jump to the start tick
	if (fromTick >= 0)
		MDPointerJumpToTick(pointer, fromTick);
	pos = MDPointerGetPosition(pointer);

	if (pointSet != nil)
		pset = [pointSet pointSet];
	else pset = NULL;
	if (pset != NULL) {
		if (!IntGroupLookup(pset, pos, &psetIndex)) {
			//  Move forward until the position is included in pset
			int32_t pos1;
			for (i = 0; (pos1 = IntGroupGetStartPoint(pset, i)) >= 0; i++) {
				if (pos1 >= pos)
					break;
			}
			if (pos1 < 0) {
				MDPointerRelease(pointer);
				return nil;  //  No such events
			}
			psetIndex = i;
			MDPointerSetPosition(pointer, pos1);
			pos = MDPointerGetPosition(pointer);
		}
	}
	
	//  Create an empty set
	resultSet = IntGroupNew();
	if (resultSet == NULL) {
		MDPointerRelease(pointer);
		return nil;
	}

	//  Loop until the tick exceeds toTick or the pointSet exhausts
	ep = MDPointerCurrent(pointer);
	while (ep != NULL && MDGetTick(ep) <= toTick) {
		BOOL ok = NO;
		if (eventKind == -1 || eventKind == MDGetKind(ep)) {
			if (eventKind == kMDEventControl || eventKind == kMDEventKeyPres) {
				//  Check the code
				if (eventCode == -1 || eventCode == MDGetCode(ep)) {
					//  Check the data range
					if (MDGetData1(ep) >= fromData && MDGetData1(ep) <= toData)
						ok = YES;
				}
			} else if (eventKind == kMDEventNote) {
				//  The data range is key code
				if (MDGetCode(ep) >= fromData && MDGetCode(ep) <= toData)
					ok = YES;
			} else {
				if (MDGetData1(ep) >= fromData && MDGetData1(ep) <= toData)
					ok = YES;
			}
		}
		if (ok)
			IntGroupAdd(resultSet, MDPointerGetPosition(pointer), 1);
		if (pset != NULL)
			ep = MDPointerForwardWithPointSet(pointer, pset, &psetIndex);
		else
			ep = MDPointerForward(pointer);
	}
	
	retObj = [[[MDSelectionObject allocWithZone: [self zone]] initWithMDPointSet: resultSet] autorelease]; 
	MDPointerRelease(pointer);
	IntGroupRelease(resultSet);
	return retObj;
}

- (int32_t)countMIDIEventsForTrack: (int32_t)index inSelection: (MDSelectionObject *)sel
{
	MDEvent *ep;
	MDTrack *track = [[self myMIDISequence] getTrackAtIndex: index];
	MDPointer *pt = MDPointerNew(track);
	IntGroup *pset = [sel pointSet];
	int32_t count = 0;
	int n = -1;
	while ((ep = MDPointerForwardWithPointSet(pt, pset, &n)) != NULL) {
		if (!MDIsMetaEvent(ep))
			count++;
	}
	MDPointerRelease(pt);
	return count;
}

- (BOOL)isSelectionEmptyInEditableTracks:(BOOL)editableOnly
{
	int i;
	int ntracks = (int)[selections count];
	for (i = 0; i < ntracks; i++) {
		MDSelectionObject *selection;
		if (editableOnly && ([self trackAttributeForTrack: i] & kMDTrackAttributeEditable) == 0)
			continue;
		selection = (MDSelectionObject *)[selections objectAtIndex: i];
		if (IntGroupGetCount([selection pointSet]) > 0)
			return NO;
	}
	return YES;
}

#pragma mark ==== Menu Commands ====

- (IBAction)performStartPlay: (id)sender
{
	[[(GraphicWindowController *)mainWindowController playingViewController] pressPlayButton: sender];
}

- (IBAction)performStopPlay: (id)sender
{
	[[(GraphicWindowController *)mainWindowController playingViewController] pressStopButton: sender];
}

- (IBAction)performPausePlay: (id)sender
{
	[[(GraphicWindowController *)mainWindowController playingViewController] pressPauseButton: sender];
}

- (IBAction)performStartMIDIRecording: (id)sender
{
	[[(GraphicWindowController *)mainWindowController playingViewController] recordButtonPressed: sender audioFlag: NO];
}

- (IBAction)performStartAudioRecording: (id)sender
{
	[[(GraphicWindowController *)mainWindowController playingViewController] recordButtonPressed: sender audioFlag: YES];
}

- (IBAction)insertBlankTime:(id)sender
{
	int32_t trackNo;
	MDTickType deltaTick;
	MDTickType startTick, endTick;
	NSWindowController *cont = [[NSApp mainWindow] windowController];

	if (startEditingRange < 0 || startEditingRange >= endEditingRange)
		return;  /*  Do nothing  */

	startTick = startEditingRange;
	endTick = endEditingRange;
	
	/* Register undo for editing range */
	[[[self undoManager] prepareWithInvocationTarget:self]
	 setEditingRangeStart:startTick end:endTick]; 

	deltaTick = endTick - startTick;
	for (trackNo = [[self myMIDISequence] trackCount] - 1; trackNo >= 0; trackNo--) {
		MDTrack *track = [[self myMIDISequence] getTrackAtIndex:trackNo];
		MDPointer *pt;
		id psobj;
		int32_t n1, n2;
		if (![cont isFocusTrack:trackNo])
			continue;

		/*  Register undo for selection change */
		psobj = [self selectionOfTrack:trackNo];
		[[[self undoManager] prepareWithInvocationTarget: self]
		 setSelection:psobj inTrack:trackNo sender:self];	

		/*  Change track duration  */
		[self changeTrackDuration:MDTrackGetDuration(track) + deltaTick ofTrack:trackNo];

		/*  Shift events  */
		pt = MDPointerNew(track);
		MDPointerJumpToTick(pt, startTick);
		n1 = MDPointerGetPosition(pt);
		n2 = MDTrackGetNumberOfEvents(track) - n1;
		if (n2 > 0) {
			psobj = [[IntGroupObject allocWithZone:[self zone]] init];
			IntGroupAdd([psobj pointSet], n1, n2);
            [self modifyTick:[NSNumber numberWithLong:deltaTick] ofMultipleEventsAt:psobj inTrack:trackNo mode:MyDocumentModifyAdd destinationPositions:nil setSelection:NO];
			[psobj release];
		}
		MDPointerRelease(pt);
	}
	
	/*  Clear selection and select inserted blank time  */
	[self unselectAllEventsInAllTracks:self];
	[self setEditingRangeStart:startTick end:endTick];
}

- (IBAction)deleteSelectedTime:(id)sender
{
	int32_t trackNo;
	MDTickType deltaTick;
	MDTickType startTick, endTick;
	NSWindowController *cont = [[NSApp mainWindow] windowController];
	
	if (startEditingRange < 0 || startEditingRange >= endEditingRange)
		return;  /*  Do nothing  */
	
	startTick = startEditingRange;
	endTick = endEditingRange;
	
	/* Register undo for editing range */
	[[[self undoManager] prepareWithInvocationTarget:self]
	 setEditingRangeStart:startTick end:endTick]; 
	
	deltaTick = endTick - startTick;
	for (trackNo = [[self myMIDISequence] trackCount] - 1; trackNo >= 0; trackNo--) {
		MDTrack *track = [[self myMIDISequence] getTrackAtIndex:trackNo];
		MDPointer *pt;
		id psobj;
		int32_t n1, n2;
		if (![cont isFocusTrack:trackNo])
			continue;
		
		/*  Register undo for selection change */
		psobj = [self selectionOfTrack:trackNo];
		[[[self undoManager] prepareWithInvocationTarget: self]
		 setSelection:psobj inTrack:trackNo sender:self];	
		
		/*  Remove events between startTick and endTick  */
		pt = MDPointerNew(track);
		if (MDPointerJumpToTick(pt, startTick) && (n1 = MDPointerGetPosition(pt)) >= 0) {
			MDPointerJumpToTick(pt, endTick);
			n2 = MDPointerGetPosition(pt) - n1;
			psobj = [[IntGroupObject allocWithZone:[self zone]] init];
			if (n2 > 0) {
				IntGroupAdd([psobj pointSet], n1, n2);
				[self deleteMultipleEventsAt:psobj fromTrack:trackNo deletedEvents:NULL];
			}
			
			/*  Shift events after endTick  */
			n2 = MDTrackGetNumberOfEvents(track) - n1;
			if (n2 > 0) {
				IntGroupClear([psobj pointSet]);
				IntGroupAdd([psobj pointSet], n1, n2);
                [self modifyTick:[NSNumber numberWithLong:-deltaTick] ofMultipleEventsAt:psobj inTrack:trackNo mode:MyDocumentModifyAdd destinationPositions:nil setSelection:NO];
			}
			[psobj release];
		}
		MDPointerRelease(pt);

		/*  Change track duration  */
		[self changeTrackDuration:MDTrackGetDuration(track) - deltaTick ofTrack:trackNo];
	}
	
	/*  Clear selection and select the start tick  */
	[self unselectAllEventsInAllTracks:self];
	[self setEditingRangeStart:startTick end:startTick];
}

- (BOOL)scaleTimeFrom:(MDTickType)startTick to:(MDTickType)endTick newDuration:(MDTickType)newDuration insertTempo:(BOOL)insertTempo setSelection:(BOOL)setSelection
{
	int32_t trackNo;
	MDTickType deltaTick;
	MDTrack *track;
	MDPointer *pt;
	MDEvent *ep;
    id psobj, dt;
	NSWindowController *cont = [[NSApp mainWindow] windowController];
	
	if (startTick < 0 || startTick >= endTick)
		return NO;  /*  Do nothing  */
	
	/* Register undo for editing range */
	[[[self undoManager] prepareWithInvocationTarget:self]
	 setEditingRangeStart:startEditingRange end:endEditingRange]; 
	
	deltaTick = endTick - startTick;
	
	/*  Modify tempo if specified  */
	if (insertTempo) {

		/*  Insert new Tempo events if not present at the borders  */
		MDEventObject *newEvent;
		MDCalibrator *calib = [[self myMIDISequence] sharedCalibrator];
		float tempo;
		MDCalibratorJumpToTick(calib, startTick);
		tempo = MDCalibratorGetTempo(calib);
		ep = MDCalibratorGetEvent(calib, NULL, kMDEventTempo, -1);
		if (ep == NULL || MDGetTick(ep) != startTick) {
			newEvent = [[MDEventObject allocWithZone: [self zone]] init];
			ep = &(newEvent->event);
			MDSetTick(ep, startTick);
			MDSetKind(ep, kMDEventTempo);
			MDSetTempo(ep, tempo);
			[self insertEvent: newEvent toTrack: 0];
			[newEvent release];
		}
		MDCalibratorJumpToTick(calib, endTick);
		tempo = MDCalibratorGetTempo(calib);
		ep = MDCalibratorGetEvent(calib, NULL, kMDEventTempo, -1);
		if (ep == NULL || MDGetTick(ep) != endTick) {
			newEvent = [[MDEventObject allocWithZone: [self zone]] init];
			ep = &(newEvent->event);
			MDSetTick(ep, endTick);
			MDSetKind(ep, kMDEventTempo);
			MDSetTempo(ep, tempo);
			[self insertEvent: newEvent toTrack: 0];
			[newEvent release];
		}
		/*  All tempo should be multiplied by ((double)newDuration)/(deltaTick)  */
		track = [[self myMIDISequence] getTrackAtIndex:0];
		pt = MDPointerNew(track);
		MDPointerJumpToTick(pt, startTick);
		psobj = [[IntGroupObject allocWithZone:[self zone]] init];
		for (ep = MDPointerCurrent(pt); ep != NULL; ep = MDPointerForward(pt)) {
			if (MDGetTick(ep) >= endTick)
				break;
			if (MDGetKind(ep) != kMDEventTempo)
				continue;
			IntGroupAdd([psobj pointSet], MDPointerGetPosition(pt), 1);
		}
		[self modifyData:[NSNumber numberWithDouble:(double)newDuration/deltaTick] forEventKind:kMDEventTempo ofMultipleEventsAt:psobj inTrack:0 mode:MyDocumentModifyMultiply];
		MDPointerRelease(pt);
		[psobj release];
	}
	
	for (trackNo = [[self myMIDISequence] trackCount] - 1; trackNo >= 0; trackNo--) {
        int32_t n1, n2, n3;
        MDTickType oldDuration, tick1, tick2;

		if (![cont isFocusTrack:trackNo] && (!insertTempo || trackNo != 0))
			continue;
		track = [[self myMIDISequence] getTrackAtIndex:trackNo];
		oldDuration = MDTrackGetDuration(track);

		/*  Register undo for selection change */
		psobj = [self selectionOfTrack:trackNo];
        if (setSelection) {
            [[[self undoManager] prepareWithInvocationTarget: self]
             setSelection:psobj inTrack:trackNo sender:self];
        }

		/*  Scale events between startTick and endTick  */
		pt = MDPointerNew(track);
		n2 = MDTrackGetNumberOfEvents(track);
		if (MDPointerJumpToTick(pt, startTick)) {
			n1 = MDPointerGetPosition(pt);
		} else {
			n1 = n2;
		}
		if (n1 < n2) {
			MDTickType *mp;
            IntGroup *ig;
            int n;
            /*  Modify note durations: should scan from the top of the track  */
            MDPointerSetPosition(pt, -1);
            psobj = [[IntGroupObject allocWithZone:[self zone]] init];
            ig = [psobj pointSet];
            while ((ep = MDPointerForward(pt)) != NULL) {
                tick1 = MDGetTick(ep);
                if (tick1 >= endTick)
                    break;
                if (MDIsNoteEvent(ep)) {
                    if (tick1 + MDGetDuration(ep) >= startTick) {
                        /*  This note should be processed  */
                        IntGroupAdd(ig, MDPointerGetPosition(pt), 1);
                    }
                }
            }
            n3 = IntGroupGetCount(ig);
            dt = [[NSMutableData allocWithZone:[self zone]] initWithLength:sizeof(MDTickType) * n3];
            mp = (MDTickType *)[dt mutableBytes];
            MDPointerSetPosition(pt, -1);
            n = -1;
            while ((ep = MDPointerForwardWithPointSet(pt, ig, &n)) != NULL) {
                tick1 = MDGetTick(ep);
                tick2 = tick1 + MDGetDuration(ep);
                if (tick2 < endTick)
                    tick2 = (MDTickType)(startTick + ((double)tick2 - startTick) * newDuration / (endTick - startTick));
                else
                    tick2 += newDuration - (endTick - startTick);
                if (tick1 >= startTick)
                    tick1 = (MDTickType)(startTick + ((double)tick1 - startTick) * newDuration / (endTick - startTick));
                *mp++ = tick2 - tick1;
            }
            [self modifyDurations:dt ofMultipleEventsAt:psobj inTrack:trackNo mode:MyDocumentModifySet];
            [dt release];
            [psobj release];
            
            /*  The ticks are modified  */
            psobj = [[IntGroupObject allocWithZone:[self zone]] init];
            dt = [[NSMutableData allocWithZone:[self zone]] initWithLength:sizeof(MDTickType) * (n2 - n1)];
            mp = (MDTickType *)[dt mutableBytes];
            MDPointerSetPosition(pt, n1);
            IntGroupAdd([psobj pointSet], n1, n2 - n1);
            mp = (MDTickType *)[dt mutableBytes];
			for (ep = MDPointerCurrent(pt); ep != NULL; ep = MDPointerForward(pt)) {
				MDTickType tick = MDGetTick(ep);
				if (tick < endTick)
                    tick = startTick + (MDTickType)(((double)tick - startTick) * newDuration / (endTick - startTick));
				else
					tick += newDuration - (endTick - startTick);
				*mp++ = tick;
			}
            [self modifyTick:dt ofMultipleEventsAt:psobj inTrack:trackNo mode:MyDocumentModifySet destinationPositions:nil setSelection:NO];
            [dt release];
            [psobj release];
            
			/*  Select events in the scaled time region  */
            if (setSelection) {
                psobj = [[MDSelectionObject allocWithZone:[self zone]] init];
                MDPointerJumpToTick(pt, startTick + newDuration);
                n2 = MDPointerGetPosition(pt) - n1;
                IntGroupAdd([psobj pointSet], n1, n2);
                [self setSelection:psobj inTrack:trackNo sender:self];
                [psobj release];
            }

		} else {
			/*  No events to shift: unselect all events in the track  */
            if (setSelection) {
                [self unselectAllEventsInTrack:trackNo sender:self];
            }
		}
		MDPointerRelease(pt);
		[self changeTrackDuration:oldDuration + (newDuration - deltaTick) ofTrack:trackNo];
	}
	
	/*  Set editing range to the scaled time region  */
	[self setEditingRangeStart:startTick end:startTick + newDuration];
    
    return YES;
}

/* See also: -[TimeChartView scaleSelectedTimeWithEvent:undoEnabled:]  */
- (IBAction)scaleSelectedTime:(id)sender
{
	double *dp;
	int n, status;
	status = Ruby_callMethodOfDocument("scale_selected_time_dialog", self, 0, ";D", &n, &dp);
	if (status != 0) {
		Ruby_showError(status);
		return;
	}
	if (n > 0) {
        [self scaleTimeFrom:(float)dp[0] to:(float)dp[1] newDuration:(float)dp[2] insertTempo:(float)dp[3] setSelection:YES];
		free(dp);
	}
}

- (IBAction)quantizeSelectedEvents:(id)sender
{
	int result;
	QuantizePanelController *cont = [[QuantizePanelController alloc] init];
	[cont setTimebase:[self timebase]];
	result = (int)[NSApp runModalForWindow:[cont window]];
	[cont close];
	[cont release];
	if (result == NSRunStoppedResponse) {
		float note, strength, swing;
		int trackNo;
		NSMutableData *dt = [NSMutableData data];
		MDCalibrator *calib = [[self myMIDISequence] sharedCalibrator];
		NSWindowController *mainCont = [[NSApp mainWindow] windowController];
		id obj = MyAppCallback_getObjectGlobalSettings(QuantizeNoteKey);
		note = (obj ? [obj floatValue] : [self timebase]);
		obj = MyAppCallback_getObjectGlobalSettings(QuantizeStrengthKey);
		strength = (obj ? [obj floatValue] : 1.0f);
		obj = MyAppCallback_getObjectGlobalSettings(QuantizeSwingKey);
		swing = (obj ? [obj floatValue] : 0.5f);
		for (trackNo = [[self myMIDISequence] trackCount] - 1; trackNo >= 1; trackNo--) {
			MDTickType *tptr;
			int32_t n1, n2;
			int index;
			MDTrack *track;
			MDTickType baseTick, nextBaseTick;
			int32_t baseMeasure;
			IntGroupObject *psobj;
			IntGroup *pset;
			MDPointer *pt;
			MDEvent *ep;
			if (![mainCont isFocusTrack:trackNo])
				continue;
			track = [[self myMIDISequence] getTrackAtIndex:trackNo];
			psobj = [self selectionOfTrack:trackNo];
			if (psobj == nil || (pset = [psobj pointSet]) == NULL || (n1 = IntGroupGetCount(pset)) == 0)
				continue;
			[dt setLength:sizeof(MDTickType) * n1];
			tptr = (MDTickType *)[dt mutableBytes];
			pt = MDPointerNew(track);
			index = -1;
			baseMeasure = -1;
			n1 = 0;
			while ((ep = MDPointerForwardWithPointSet(pt, pset, &index)) != NULL) {
				double d;
				MDTickType etick = MDGetTick(ep);
				MDTickType targetTick;
				if (baseMeasure < 0) {
					int32_t beat, tick;
					MDCalibratorTickToMeasure(calib, etick, &baseMeasure, &beat, &tick);
					baseTick = MDCalibratorMeasureToTick(calib, baseMeasure, 0, 0);
					nextBaseTick = MDCalibratorMeasureToTick(calib, ++baseMeasure, 0, 0);
				} else if (etick >= nextBaseTick) {
					baseTick = nextBaseTick;
					nextBaseTick = MDCalibratorMeasureToTick(calib, ++baseMeasure, 0, 0);
				}
				d = (double)(etick - baseTick) / (note * 2.0);
				n2 = (int)floor(d);
				d -= n2;
				targetTick = baseTick + n2 * note * 2;
				/*
				+-------------+---|-------+
				0             1  1+swing  2
				*/
				if (d < 0.25 + swing * 0.25) {
					/*  Use above targetTick  */
				} else if (d < 0.75 + swing * 0.25) {
					targetTick += note * (1 + swing);
				} else {
					targetTick += note * 2;
				}
				etick = (int)floor(etick + (targetTick - etick) * strength + 0.5);
				tptr[n1++] = etick;
			}
            [self modifyTick:dt ofMultipleEventsAt:psobj inTrack:trackNo mode:MyDocumentModifySet destinationPositions:nil setSelection:NO];
			MDPointerRelease(pt);
		}
	}
}

- (IBAction)getEditingRangeFromPasteboard:(id)sender
{
	MDCatalog *catalog;
	
	if (![self getPasteboardSequence: NULL catalog: &catalog])
		return;
	[self setEditingRangeStart:catalog->startTick end:catalog->endTick];
	free(catalog);
}

- (BOOL)validateUserInterfaceItem: (id)anItem
{
	SEL sel = [anItem action];
	if (sel == @selector(performStartPlay:) || sel == @selector(performStartMIDIRecording:)
        /* || sel == @selector(performStopMIDIRecording:) */ ) {
		return ![[self myMIDISequence] isPlaying];
	} else if (sel == @selector(performStopPlay:) || sel == @selector(performPausePlay:)) {
		return [[self myMIDISequence] isPlaying];
	} else if (sel == @selector(insertBlankTime:) || sel == @selector(deleteSelectedTime:) || sel == @selector(scaleSelectedTime:)) {
		MDTickType startTick, endTick;
		[self getEditingRangeStart:&startTick end:&endTick];
		return (startTick < endTick);
	} else if (sel == @selector(quantizeSelectedEvents:)) {
		return [self isSelectionEmptyInEditableTracks:YES] == NO;
	} else if (sel == @selector(getEditingRangeFromPasteboard:)) {
		return [self isSequenceInPasteboard];
	}
	return [super validateUserInterfaceItem:anItem];
}

#pragma mark ====== Script Menu ======

/*
- (NSMutableArray *)scriptMenuInfos
{
	return scriptMenuInfos;
}

- (void)doDocumentScriptCommand: (id)sender
{
	[[NSApp delegate] performScriptCommandForTitle: [sender title] forDocument: self];
}
*/

#pragma mark ====== Pasteboard support ======

- (BOOL)copyWithSelections: (MDSelectionObject **)selArray rangeStart: (MDTickType)startTick rangeEnd: (MDTickType)endTick
{
	IntGroup **psetArray;
	char *eotSelectFlags;
	MDCatalog *catalog;
	MDSelectionObject *sel;
	MDStatus sts;
	void *streamPtr;
	size_t streamSize;
	NSData *seqData, *catData;
	int i, j, numberOfSelectedTracks, catLength;
	STREAM sp;
	MyMIDISequence *seq = [self myMIDISequence];
	int numberOfTracks = [seq trackCount];

	psetArray = (IntGroup **)calloc(sizeof(IntGroup *), numberOfTracks);
	if (psetArray == NULL)
		return NO;
	eotSelectFlags = (char *)calloc(sizeof(char), numberOfTracks);
	if (eotSelectFlags == NULL)
		return NO;

	seqData = catData = nil;

	numberOfSelectedTracks = 0;
	for (i = 0; i < numberOfTracks; i++) {
		/*  Convert selArray data to psetArray  */
		sel = selArray[i];
		if (sel == nil)
			continue;
		numberOfSelectedTracks++;
		if (sel == (MDSelectionObject *)(-1)) {
			psetArray[i] = (IntGroup *)(-1);
			eotSelectFlags[i] = 1;
		} else {
			psetArray[i] = [sel pointSet];
			eotSelectFlags[i] = sel->isEndOfTrackSelected;
		}
	}
	
	/*  Dump SMF to memory  */
	sp = MDStreamOpenData(NULL, 0);
	if (sp == NULL)
		return NO;

	sts = MDSequenceWriteSMFWithSelection([seq mySequence], psetArray, eotSelectFlags, sp, NULL, NULL);
	if (sts != kMDNoError)
		return NO;

	MDStreamGetData(sp, &streamPtr, &streamSize);
	FCLOSE(sp);
	seqData = [NSData dataWithBytesNoCopy: streamPtr length: streamSize freeWhenDone: YES];

	/*  Create catalog  */
	catLength = sizeof(MDCatalog) + (numberOfSelectedTracks - 1) * sizeof(MDCatalogTrack);
	catalog = (MDCatalog *)calloc(catLength, 1);
	if (catalog == NULL)
		return NO;

	catalog->num = numberOfSelectedTracks;
	catalog->startTick = startTick;
	catalog->endTick = endTick;
	for (i = j = 0; i < numberOfTracks; i++) {
		MDCatalogTrack *cat;
		MDTrack *track;
		if (psetArray[i] == NULL)
			continue;
		if (j >= numberOfSelectedTracks)
			break;  /*  This cannot happen  */
		cat = catalog->catTrack + j;
		cat->originalTrackNo = i;
		track = [seq getTrackAtIndex: i];
		MDTrackGetName(track, cat->name, sizeof(cat->name));
		if (psetArray[i] == (IntGroup *)(-1)) {
			cat->numEvents = MDTrackGetNumberOfEvents(track);
			cat->numMIDIEvents = cat->numEvents - MDTrackGetNumberOfNonMIDIEvents(track);
		} else {
			cat->numEvents = IntGroupGetCount(psetArray[i]);
			cat->numMIDIEvents = [self countMIDIEventsForTrack: i inSelection: selArray[i]];
		}
		j++;
	}
	sp = MDStreamOpenData(NULL, 0);
	if (sp == NULL)
		return NO;
	sts = MDSequenceWriteCatalog(catalog, sp);
	if (sts != kMDNoError)
		return NO;
	MDStreamGetData(sp, &streamPtr, &streamSize);
	FCLOSE(sp);
	catData = [NSData dataWithBytesNoCopy: streamPtr length: streamSize freeWhenDone: YES];
	free(catalog);
	
	if (seqData != nil && catData != nil) {
		NSPasteboard *pb = [NSPasteboard generalPasteboard];
		NSArray *types = [NSArray arrayWithObjects: MySequencePBoardType, MySeqCatalogPBoardType, nil];
		[pb declareTypes: types owner: self];
		[pb setData: seqData forType: MySequencePBoardType];
		[pb setData: catData forType: MySeqCatalogPBoardType];
	}

	free(psetArray);
	free(eotSelectFlags);
	
	return YES;
}

- (BOOL)isSequenceInPasteboard
{
	NSArray *types = [[NSPasteboard generalPasteboard] types];
	if ([types containsObject: MySequencePBoardType] && [types containsObject: MySeqCatalogPBoardType])
		return YES;
	else return NO;
}

- (BOOL)getPasteboardSequence: (MDSequence **)outSequence catalog: (MDCatalog **)outCatalog
{
	MDCatalog *catalog;
	MDSequence *seq;
	NSData *seqData, *catData;
	NSPasteboard *pb;
	MDStatus sts;
	STREAM sp;

	if (![self isSequenceInPasteboard])
		return NO;

	pb = [NSPasteboard generalPasteboard];
	catData = [pb dataForType: MySeqCatalogPBoardType];
	seqData = [pb dataForType: MySequencePBoardType];
	
	if (outSequence != NULL) {
		sp = MDStreamOpenData((void *)[seqData bytes], [seqData length]);
		if (sp == NULL)
			return NO;
		seq = MDSequenceNew();
		if (seq == NULL)
			return NO;
		sts = MDSequenceReadSMF(seq, sp, NULL, NULL);
		FCLOSE(sp);
		if (sts != kMDNoError)
			return NO;
		/*  Make it single channel (without separating the multi-channel track)  */
		MDSequenceSingleChannelMode(seq, 0);
	} else seq = NULL;

	sp = MDStreamOpenData((void *)[catData bytes], [catData length]);
	if (sp == NULL)
		return NO;
	catalog = MDSequenceReadCatalog(sp);
	FCLOSE(sp);
	if (catalog == NULL) {
		if (seq != NULL)
			MDSequenceRelease(seq);
		return NO;
	}
	
	if (outSequence != NULL)
		*outSequence = seq;

	if (outCatalog != NULL)
		*outCatalog = catalog;
	else free(catalog);
	
	return YES;
}

static int
isConductorEvent(const MDEvent *ep, int32_t position, void *inUserData)
{
	if (ep == NULL)
		return 0;
	switch (MDGetKind(ep)) {
		case kMDEventTempo:
		case kMDEventTimeSignature:
		case kMDEventSMPTE:
			return 1;
		default:
			return 0;
	}
}

- (int)doPaste: (MDSequence *)seq toTracks: (int *)trackList rangeStart: (MDTickType)startTick rangeEnd: (MDTickType)endTick mergeFlag: (BOOL)mergeFlag
{
	MDTickType tickOffset;
	int i, numberOfTracks;
	MDTrack *track, *conductorTrack;
	MDSelectionObject *sel;
	int trackCount = [[self myMIDISequence] trackCount];

	conductorTrack = NULL;

	numberOfTracks = MDSequenceGetNumberOfTracks(seq);
	if (numberOfTracks == 0)
		return 0;  /*  Do nothing  */

	/*  Tick offset  */
	if (startTick < 0)
		startTick = 0;
	if (endTick == kMDMaxTick)
		endTick = MDSequenceGetDuration(seq);
	if (startEditingRange < 0)
		tickOffset = 0;
	else {
		tickOffset = startEditingRange - startTick;
		for (i = 0; i < numberOfTracks; i++) {
			MDTrackOffsetTick(MDSequenceGetTrack(seq, i), tickOffset);
		}
	}
	
	/*  Check the first track in the list  */
	if (trackList[0] == 0) {
		int32_t n;
		/*  The first target track is the conductor track; MIDI events must not go into this track  */
		track = MDSequenceGetTrack(seq, 0);
		n = MDTrackGetNumberOfEvents(track);
		if (MDTrackGetNumberOfNonMIDIEvents(track) < n)
			return 1;  /*  Try to insert MIDI events to the conductor track  */
	} else {
		/*  The first target track is the non-conductor track  */
		IntGroup *pset;
		track = MDSequenceGetTrack(seq, 0);
		pset = MDTrackSearchEventsWithSelector(track, isConductorEvent, NULL);
		if (pset == NULL)
			return -1;  /*  Out of memory  */
		if (IntGroupGetCount(pset) > 0) {
			/*  The conductor-only events must go into the conductor track  */
			if (MDTrackUnmerge(track, &conductorTrack, pset) != kMDNoError)
				return -1;  /*  Out of memory  */
		}
		IntGroupRelease(pset);
	}
	
	/*  Delete existing events in the 'editing range'  */
	if (!mergeFlag) {
		for (i = 0; i < numberOfTracks; i++) {
			if (trackList[i] < 0 || trackList[i] >= trackCount)
				continue;
			sel = [self eventSetInTrack: trackList[i] eventKind: -1 eventCode: -1 fromTick: startTick + tickOffset toTick: endTick + tickOffset fromData: -32768 toData: 32768 inPointSet: nil];
			if (sel != nil)
				[self deleteMultipleEventsAt: sel fromTrack: trackList[i] deletedEvents: NULL];
		
		}
	}
	
	/*  Deselect all events  */
	[self unselectAllEventsInAllTracks:self];

	/*  Merge new events  */
	for (i = 0; i < numberOfTracks; i++) {
		int newTrackNo = trackList[i];
		if (trackList[i] >= trackCount) {
			[self insertTrack: nil atIndex: trackCount];
			newTrackNo = trackCount;
			trackCount++;
		}
		[self insertMultipleEvents: [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: MDSequenceGetTrack(seq, i)] autorelease] at: nil toTrack: newTrackNo selectInsertedEvents: YES insertedPositions: NULL];
	}
	
	/*  Merge conductor-only events  */
	if (conductorTrack != NULL) {
		[self insertMultipleEvents: [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: conductorTrack] autorelease] at: nil toTrack: 0 selectInsertedEvents: YES insertedPositions: NULL];
		MDTrackRelease(conductorTrack);
	}
	
	/*  Set editing range  */
	if (startTick >= 0) {
		[self setEditingRangeStart: startTick + tickOffset end: endTick + tickOffset];
	}
	
	return 0;
}

#pragma mark ====== Recording support ======

- (BOOL)startRecording
{
    if ([[self myMIDISequence] startMIDIRecording] == kMDNoError)
        return YES;
    else return NO;
}

- (BOOL)finishRecording
{
	MyMIDISequence *seq;
    MDTrackObject *newTrack;
    int32_t recIndex;
    MDTickType startTick, endTick, currentTick;
    MDTimeType currentTime;
    NSDictionary *info;
	static unsigned char remapTable[] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
	
	seq = [self myMIDISequence];
    info = [seq recordingInfo];
    currentTime = MDPlayerGetTime([seq myPlayer]);
    currentTick = MDCalibratorTimeToTick([seq sharedCalibrator], currentTime);
    if ([[info valueForKey: MyRecordingInfoStopFlagKey] boolValue]) {
        endTick = (int)[[info valueForKey: MyRecordingInfoStopTickKey] doubleValue];
        if (currentTick < endTick)
            endTick = currentTick;
    } else endTick = currentTick;
	newTrack = [seq finishMIDIRecording];
	MDTrackSetDuration([newTrack track], endTick);
	if (newTrack != nil) {
		int destChannel;
		recIndex = [[info valueForKey: MyRecordingInfoTargetTrackKey] intValue];
		startTick = (int)[[info valueForKey: MyRecordingInfoStartTickKey] doubleValue];
		if (recIndex < 0 || recIndex >= [seq trackCount]) {
			recIndex = [seq trackCount];
			destChannel = [[info valueForKey: MyRecordingInfoDestinationChannelKey] intValue];
			if (destChannel < 0 || destChannel >= 16) {
				//  Split track by channel
				MDTrack *splitTracks[16];
				int n = MDTrackSplitByMIDIChannel([newTrack track], splitTracks);
				if (n == 0)
					return NO;
				for (n = 0; n < 16; n++) {
					MDTrackObject *splitNewTrack;
					if (splitTracks[n] == NULL)
						continue;
					if (splitTracks[n] == [newTrack track])
						splitNewTrack = newTrack;
					else {
						splitNewTrack = [[[MDTrackObject allocWithZone: [self zone]] initWithMDTrack: splitTracks[n]] autorelease];
						MDTrackRelease(splitTracks[n]);  /*  This is retained in splitNewTrack  */
					}
					if (![self insertTrack: splitNewTrack atIndex: recIndex])
						return NO;
					[self changeTrackChannel: n forTrack: recIndex];
					recIndex++;
				}
			} else {
				//  The channel information is cleared
				MDTrackRemapChannel([newTrack track], remapTable);
				if (![self insertTrack: newTrack atIndex: recIndex])
					return NO;
				[self changeTrackChannel: destChannel forTrack: recIndex];
			}
			return YES;
		} else {
			if ([[info valueForKey: MyRecordingInfoReplaceFlagKey] boolValue]) {
				//  Delete events from startTick to endTick
				MDSelectionObject *sel = [self eventSetInTrack: recIndex eventKind: -1 eventCode: -1 fromTick: startTick toTick: endTick fromData: -32768 toData: 32768 inPointSet: nil];
				if (![self deleteMultipleEventsAt: sel fromTrack: recIndex deletedEvents: NULL])
					return NO;
			}
			//  The channel information is cleared
			MDTrackRemapChannel([newTrack track], remapTable);
			return [self insertMultipleEvents: newTrack at: nil toTrack: recIndex selectInsertedEvents: YES insertedPositions: NULL];
		}
	}
	return NO;
//    if ([[self myMIDISequence] finishMIDIRecordingAndGetTrack: &newTrack andTrackIndex: &recIndex] == kMDNoError) {
//        return [self insertMultipleEvents: newTrack at: nil toTrack: recIndex];
//    } else return NO;
}

- (BOOL)startAudioRecording
{
//	NSString *filename, *docname, *docdir;
	NSString *dirname, *filename, *fullname;
	NSString *errmsg = nil;
	MDTickType startTick;
	BOOL isDir;
	NSDictionary *info = [[self myMIDISequence] recordingInfo];
	NSFileManager *manager = [NSFileManager defaultManager];
	dirname = [info valueForKey: MyRecordingInfoFolderNameKey];
	filename = [info valueForKey: MyRecordingInfoFileNameKey];
	if (dirname == nil) {
		dirname = [@"~/Music" stringByExpandingTildeInPath];
		if (![manager fileExistsAtPath: dirname])
            [manager createDirectoryAtPath:dirname withIntermediateDirectories:YES attributes:nil error:NULL];
	} else dirname = [dirname stringByExpandingTildeInPath];
	if (![manager fileExistsAtPath: dirname isDirectory: &isDir] || !isDir) {
		errmsg = [NSString stringWithFormat: @"There is no directory at %@", [dirname stringByAbbreviatingWithTildeInPath]];
		goto error;
	}
	if (filename == nil)
		filename = [NSString stringWithFormat: @"audio.%@", MyRecordingInfoFileExtensionForFormat([[info valueForKey: MyRecordingInfoAudioRecordingFormatKey] intValue])];
	fullname = [dirname stringByAppendingPathComponent: filename];
	if ([manager fileExistsAtPath: fullname]) {
		if ([[info valueForKey: MyRecordingInfoOverwriteExistingFileFlagKey] boolValue]) {
            [manager removeItemAtURL:[NSURL fileURLWithPath:fullname] error:NULL];
		} else {
			//  Ask whether to overwrite the existing file
			int retval = (int)NSRunCriticalAlertPanel(@"", [NSString stringWithFormat: @"The file %@ already exists. Do you want to overwrite it?", filename], @"Cancel", @"Overwrite", @"Save with modified name", nil);
			switch (retval) {
				case NSAlertDefaultReturn: return NO;
				case NSAlertAlternateReturn: {
                    [manager removeItemAtURL:[NSURL fileURLWithPath:fullname] error:NULL];
					break;
				}
				case NSAlertOtherReturn: {
					//  Try to rename the file
					int i = 1;
					while (1) {
						NSString *newname = [[NSString stringWithFormat: @"%@_%d", [fullname stringByDeletingPathExtension], i] stringByAppendingPathExtension: [fullname pathExtension]];
						if (![manager fileExistsAtPath: newname]) {
							fullname = newname;
							filename = [fullname lastPathComponent];
							break;
						}
						i++;
					}
					break;
				}
			}
		}
	}
	startTick = (int)[[info valueForKey: MyRecordingInfoStartTickKey] doubleValue];
    if ([[self myMIDISequence] startAudioRecordingWithName: fullname] == kMDNoError)
        return YES;
    else errmsg = @"Failed to record audio";
    error: {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Audio Recording Error"];
        [alert setInformativeText:errmsg];
        [alert runModal];
        [alert release];
    }
	return NO;
}

- (BOOL)finishAudioRecording
{
	if ([[self myMIDISequence] finishAudioRecordingByMIDISequence] == kMDNoError)
		return YES;
	else return NO;
}

@end
