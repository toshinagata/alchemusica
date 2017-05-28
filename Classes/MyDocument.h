//
//  MyDocuments.h
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

#import <Cocoa/Cocoa.h>
#import "MDHeaders.h"

@class MyMIDISequence;
@class MDEventObject;
@class MDTrackObject;
@class IntGroupObject;
@class MDSelectionObject;
@class GraphicWindowController;

//  Track was modified; info = { @"track", trackNo (int) }
extern NSString *MyDocumentTrackModifiedNotification;

//  Track was inserted; info = { @"track", trackNo (int) }
extern NSString *MyDocumentTrackInsertedNotification;

//  Track was deleted; info = { @"track", trackNo (int) }
extern NSString *MyDocumentTrackDeletedNotification;

//  Track is playing; info = { @"position", positionInQuarters (float) }
extern NSString *MyDocumentPlayPositionNotification;

//  Selection has been changed; info = { @"keys", NSArray of track numbers (plus some other info) }
extern NSString *MyDocumentSelectionDidChangeNotification;

//  Editing range has been changed; info = none
extern NSString *MyDocumentEditingRangeDidChangeNotification;

//  Track has stopped playing; info = none
//extern NSString *MyDocumentStopPlayingNotification;

//  Pasteboard types
extern NSString *MySequencePBoardType;
extern NSString *MySeqCatalogPBoardType;

typedef enum MyDocumentModifyMode {
    MyDocumentModifyNone = 0,
    MyDocumentModifySet,
    MyDocumentModifyAdd,
    MyDocumentModifyMultiply
} MyDocumentModifyMode;

@interface MyDocument : NSDocument
{
    @private
    NSData *myData;
    MyMIDISequence *myMIDISequence;
    NSMutableArray *selections;
	GraphicWindowController *mainWindowController;
	
	//  Editing range
	MDTickType startEditingRange, endEditingRange;
	BOOL needsUpdateEditingRange;
	
	//  Selection stack (for undo/redo selection)
	NSMutableArray *selectionStack;
	int selectionStackPointer;
	NSMutableDictionary *selectionQueue;
	
	//  Modified tracks (for sending track-modify-notification at the end of the runloop)
	//  An array of NSNumbers (representing the track numbers)
	NSMutableArray *modifiedTracks;

	//  Destination List
	//  The devices that have once been used in this document is remembered
	//  until this document is closed
	//  Updated in getDestinationNames (and only there)
	NSArray *destinationNames;
	
	//  Script menu
//	NSMutableArray *scriptMenuInfos;
}
- (id)init;
- (MyMIDISequence *)myMIDISequence;
- (NSString *)tuneName;

- (void)lockMIDISequence;
- (void)unlockMIDISequence;

- (void)createWindowForTracks: (NSArray *)tracks ofType: (NSString *)windowType;

- (NSArray *)getDestinationNames;

- (void)enqueueTrackModifiedNotification: (long)trackNo;
- (void)postTrackModifiedNotification: (NSNotification *)notification;
- (void)postPlayPositionNotification: (MDTickType)tick;
//- (void)postSelectionDidChangeNotification: (long)trackNo selectionChange: (IntGroupObject *)set sender: (id)sender;
//- (void)postStopPlayingNotification;

//  Action methods for undo/redo support
- (BOOL)insertTrack: (MDTrackObject *)trackObj atIndex: (long)trackNo;
- (BOOL)deleteTrackAt: (long)trackNo;

- (BOOL)setRecordFlagOnTrack: (long)trackNo flag: (int)flag;
- (BOOL)setMuteFlagOnTrack: (long)trackNo flag: (int)flag;
- (BOOL)setSoloFlagOnTrack: (long)trackNo flag: (int)flag;

- (BOOL)insertEvent: (MDEventObject *)eventObj toTrack: (long)trackNo;
- (BOOL)deleteEventAt: (long)position fromTrack: (long)trackNo;
- (BOOL)replaceEvent: (MDEventObject *)eventObj inTrack: (long)trackNo;

- (BOOL)insertMultipleEvents: (MDTrackObject *)trackObj at: (IntGroupObject *)pointSet toTrack: (long)trackNo selectInsertedEvents: (BOOL)flag insertedPositions: (IntGroup **)outPtr;
- (BOOL)deleteMultipleEventsAt: (IntGroupObject *)pointSet fromTrack: (long)trackNo deletedEvents: (MDTrack **)outPtr;
- (BOOL)duplicateMultipleEventsAt: (IntGroupObject *)pointSet ofTrack: (long)trackNo selectInsertedEvents: (BOOL)flag;

//  Modify action methods; theData is one of the following, NSNumber, NSData (an array of MDTickType, short or float) or NSArray.
- (BOOL)modifyTick: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (long)trackNo mode: (MyDocumentModifyMode)mode destinationPositions: (id)destPositions;
+ (BOOL)modifyTick: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (id)doc mode: (MyDocumentModifyMode)mode destinationPositions: (id)destPositions;
- (BOOL)modifyCodes: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (long)trackNo mode: (MyDocumentModifyMode)mode;
+ (BOOL)modifyCodes: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (MyDocument *)doc mode: (MyDocumentModifyMode)mode;
- (BOOL)modifyDurations: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (long)trackNo mode: (MyDocumentModifyMode)mode;
+ (BOOL)modifyDurations: (id)theData ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (MyDocument *)doc mode: (MyDocumentModifyMode)mode;
- (BOOL)modifyData: (id)theData forEventKind: (unsigned char)eventKind ofMultipleEventsAt: (IntGroupObject *)pointSet inTrack: (long)trackNo mode: (MyDocumentModifyMode)mode;
+ (BOOL)modifyData: (id)theData forEventKind: (unsigned char)eventKind ofMultipleEventsAt: (IntGroupObject *)pointSet forMDTrack: (MDTrack *)track inDocument: (MyDocument *)doc mode: (MyDocumentModifyMode)mode;

- (const MDEvent *)eventAtPosition: (long)position inTrack: (long)trackNo;

- (long)changeTick: (long)tick atPosition: (long)position inTrack: (long)trackNo originalPosition: (long)pos1;
- (BOOL)changeChannel: (int)channel atPosition: (long)position inTrack: (long)trackNo;
- (BOOL)changeDuration: (long)duration atPosition: (long)position inTrack: (long)trackNo;
- (BOOL)changeTrackDuration: (long)duration ofTrack: (long)trackNo;
- (BOOL)changeValue: (MDEventFieldDataWhole)wholeValue ofType: (int)code atPosition: (long)position inTrack: (long)trackNo;
- (BOOL)changeMessage: (NSData *)data atPosition: (long)position inTrack: (long)trackNo;

- (BOOL)changeDevice: (NSString *)deviceName forTrack: (long)trackNo;
//- (BOOL)changeDeviceNumber: (long)deviceNumber forTrack: (long)trackNo;
- (BOOL)changeTrackChannel: (int)channel forTrack: (long)trackNo;
- (BOOL)changeTrackName: (NSString *)trackName forTrack: (long)trackNo;

- (BOOL)setSelection: (MDSelectionObject *)set inTrack: (long)trackNo sender: (id)sender;
- (BOOL)toggleSelection: (MDSelectionObject *)set inTrack: (long)trackNo sender: (id)sender; 
- (BOOL)selectEventAtPosition: (long)position inTrack: (long)trackNo sender: (id)sender;
- (BOOL)unselectEventAtPosition: (long)position inTrack: (long)trackNo sender: (id)sender;
- (BOOL)selectAllEventsInTrack: (long)trackNo sender: (id)sender;
- (BOOL)unselectAllEventsInTrack: (long)trackNo sender: (id)sender;
- (BOOL)unselectAllEventsInAllTracks: (id)sender;
- (BOOL)addSelection: (IntGroupObject *)set inTrack: (long)trackNo sender: (id)sender;
- (BOOL)isSelectedAtPosition: (long)position inTrack: (long)trackNo;

//- (void)setNeedsUpdateEditingRange: (BOOL)flag;
- (void)getEditingRangeStart: (MDTickType *)startTick end: (MDTickType *)endTick;
- (void)setEditingRangeStart: (MDTickType)startTick end: (MDTickType)endTick;
- (void)getSelectionStartTick: (MDTickType *)startTickPtr endTick: (MDTickType *)endTickPtr editableTracksOnly: (BOOL)flag;

- (MDSelectionObject *)selectionOfTrack: (long)trackNo;

- (MDSelectionObject *)eventSetInTrack: (long)trackNo eventKind: (int)eventKind eventCode: (int)eventCode fromTick: (MDTickType)fromTick toTick: (MDTickType)toTick fromData: (float)fromData toData: (float)toData inPointSet: (IntGroupObject *)pointSet;
- (long)countMIDIEventsForTrack: (long)index inSelection: (MDSelectionObject *)sel;
- (BOOL)isSelectionEmptyInEditableTracks:(BOOL)editableOnly;

- (float)timebase;
- (void)setTimebase:(float)timebase;

//  Color management
- (NSColor *)colorForTrack: (int)track enabled: (BOOL)flag;
+ (NSColor *)colorForEditingRange;
+ (NSColor *)colorForSelectingRange;

//  Track attributes
- (NSData *)getTrackAttributes;
- (void)setTrackAttributes: (NSData *)data;
- (MDTrackAttribute)trackAttributeForTrack: (long)trackNo;
- (void)setTrackAttribute: (MDTrackAttribute)attr forTrack: (long)trackNo;
- (BOOL)isTrackSelected: (long)trackNo;
- (void)setIsTrackSelected: (long)trackNo flag: (BOOL)flag;

//  Pasteboard supports
- (BOOL)copyWithSelections: (MDSelectionObject **)selArray rangeStart: (MDTickType)startTick rangeEnd: (MDTickType)endTick;
- (BOOL)isSequenceInPasteboard;
- (BOOL)getPasteboardSequence: (MDSequence **)outSequence catalog: (MDCatalog **)outCatalog;
- (int)doPaste: (MDSequence *)seq toTracks: (int *)trackList rangeStart: (MDTickType)startTick rangeEnd: (MDTickType)endTick mergeFlag: (BOOL)mergeFlag;

//  Playing control (from main menu)
- (IBAction)performStartPlay: (id)sender;
- (IBAction)performStopPlay: (id)sender;
- (IBAction)performPausePlay: (id)sender;
- (IBAction)performStartMIDIRecording: (id)sender;
- (IBAction)performStartAudioRecording: (id)sender;

//  General editing
- (IBAction)insertBlankTime:(id)sender;
- (IBAction)deleteSelectedTime:(id)sender;
- (IBAction)scaleSelectedTime:(id)sender;
- (IBAction)quantizeSelectedEvents:(id)sender;
- (IBAction)getEditingRangeFromPasteboard:(id)sender;

//  Recording
- (BOOL)startRecording;
- (BOOL)finishRecording;
- (BOOL)startAudioRecording;
- (BOOL)finishAudioRecording;

//  Structure to keep track of MyDocument-MDTrack correspondence
//  When a track is inserted to or deleted from a document, all registered 
// MyDocumentTrackInfo are scanned and the information is updated.
//  No ownership of the memory is claimed; registerDocumentTrackInfo only
// keeps the pointer, and unregisterDocumentTrackInfo only removes the pointer
// from the internal buffer. If a MyDocumentTrackInfo block is freed without
// unregistering, disaster will come. Be careful!

typedef struct MyDocumentTrackInfo {
	MyDocument *doc;
	MDTrack *track;
	int num;
} MyDocumentTrackInfo;

+ (void)registerDocumentTrackInfo: (MyDocumentTrackInfo *)info;
+ (void)unregisterDocumentTrackInfo: (MyDocumentTrackInfo *)info;

//  Script menu
// - (NSMutableArray *)scriptMenuInfos;
// - (void)doDocumentScriptCommand: (id)sender;

@end
