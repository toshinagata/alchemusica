//
//  ListWindowController.h
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>
#import "ContextMenuTextFieldCell.h"
#import "MDHeaders.h"

@class MyMIDISequence;
@class MyTableHeaderView;
@class MyTableView;

typedef struct ListWindowFilterRecord {
	char	mode;	// 0: all, 1: only, 2: except for
	int     count;  // number of table[] entries
	struct {
		BOOL	flag;
		MDEventKind	kind;
		short	data;
	} *table;
} ListWindowFilterRecord;

@interface ListWindowController : NSWindowController <NSTableViewDataSource>
{
    IBOutlet MyTableView *myEventTrackView;
    IBOutlet NSTextField *myInfoText;
	IBOutlet NSMenu      *myTickDescriptionMenu;
	IBOutlet NSTextField *startEditingRangeText;
	IBOutlet NSTextField *endEditingRangeText;
    IBOutlet ContextMenuTextFieldCell *kindDataCell;
    IBOutlet ContextMenuTextFieldCell *dataDataCell;
    
	MDTrack *myTrack;
	int32_t myTrackNumber;

    /*  >0 なら selectionDidChange Notification に反応しない  */
    int selectionDidChangeNotificationLevel;

	/*  myPointer が指す位置が myRow 行目になる。表示されないイベントがあるため、
	    myRow は必ずしも MDPointerGetPosition(myPointer) とは一致しない。 */
	MDPointer *myPointer;
	int32_t	myRow;

	/*  表示するイベントの数をキャッシュしておく  */
	int32_t	myCount;
	
	/*  Tick 表示のカラムの数  */
	int32_t	myTickColumnCount;
	
	/*  Tick 表示のポップアップメニューが押されたカラム  */
	NSTableColumn *myClickedColumn;
	
	MDCalibrator *myCalibrator;
	
	ListWindowFilterRecord *myFilter;
	
	/*  編集中のカラム・行位置と、そのセルの中での番号  */
	/*  編集中のセルがない場合は myEditRow が -1 になる  */
	int32_t		myEditRow;
	int32_t		myEditColumn;
	int32_t		myEditIndex;
	
	/*  Is the last row (end-of-track) selected?  */
	/*  (This information is not stored in MyMIDISequence->seletion, so it 
	    should be stored here) */
	BOOL        isLastRowSelected;
	
	/*  新たに挿入するイベント。 */
	MDEvent     myDefaultEvent;

	/*  The row containing the last event before the playing tick  */
	int32_t		myPlayingRow;

    /*  最終行（end-of-track）は通常選択を許さないが、end-of-track の時刻を編集する時だけは
        選択を一時的に許可する  */
//    BOOL        allowSelectingLastRow;
    
	/*  編集途中のイベントを保持しておく。編集中は実際のイベントのかわりにこれが表示され、
	    さらに編集途中の文字列は myEditString が表示される  */
/*	MDEvent		myEditEvent;
	
	NSString	*myEditString;
	NSTextView	*myFieldEditor; */
}

//- (void)setMIDITrack:(MDTrack *)aTrack;
//- (MDTrack *)MIDITrack;

- (MDEvent *)eventPointerForTableRow:(int)rowIndex;
- (int32_t)eventPositionForTableRow:(int)rowIndex;
- (MDTickType)eventTickForTableRow: (int)rowIndex;
- (int)rowForEventPosition: (int32_t)position nearestRow: (int *)nearestRow;
- (void)updateInfoText;
- (void)updateEditingRangeText;

/*  Notification handler  */
- (void)updateEventTableView:(NSNotification *)notification;
- (void)editingRangeChanged: (NSNotification *)notification;

- (IBAction)myAppendColumn:(id)sender;
- (IBAction)myRemoveColumn:(id)sender;
- (IBAction)myShowSecond:(id)sender;
- (IBAction)myShowBarBeatCount:(id)sender;
- (IBAction)myShowCount:(id)sender;
- (IBAction)myShowMillisecond:(id)sender;
//- (IBAction)myDoubleAction:(id)sender;
//- (IBAction)eventKindMenuSelected:(id)sender;

- (IBAction)showEditingRange:(id)sender;

- (IBAction)deleteSelectedEvents:(id)sender;

- (IBAction)insertNewEvent: (id)sender;
- (IBAction)editSelectedEvent: (id)sender;
- (void)startEditAtColumn: (int)column row: (int)row;
- (void)startEditAtColumn: (int)column creatingEventWithTick: (MDTickType)tick atPosition: (int32_t)position;

- (IBAction)editingRangeTextModified: (id)sender;

//- (void)enterEditModeForRow:(int)row andColumn:(int)column withIndex:(int)index;
//- (void)exitEditMode;
//- (BOOL)isEditMode;

//- (BOOL)tableHeaderView:(MyTableHeaderView *)headerView mouseDown:(NSEvent *)theEvent;
- (NSMenu *)tableHeaderView:(NSTableHeaderView *)headerView popUpMenuAtHeaderColumn:(int)column;

//  Tick popup handling
- (int)tagForTickIdentifier:(NSString *)identifier;
- (NSString *)tickIdentifierForTag:(int)tag;

- (void)showPlayPosition:(NSNotification *)notification;

@end
