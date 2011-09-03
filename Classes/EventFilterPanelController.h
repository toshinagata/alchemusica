//
//  EventFilterPanelController.h
//  Alchemusica
//
/*
    Copyright (c) 2008-2011 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

extern NSString *gModeKey, *gChannelPressureKey, *gNoteKey, *gPitchBendKey, *gPolyPressureKey, *gProgramKey, *gSysexKey, *gCCMetaKey;
extern NSString *gCCMetaNameKey, *gCCMetaSelectedKey, *gCCMetaNumberKey;

@interface EventFilterPanelController : NSWindowController
{
    IBOutlet NSObjectController *filters;
	IBOutlet NSArrayController *ccMetaFilters;
	IBOutlet NSPopUpButtonCell *ccMetaPopUp;
	IBOutlet NSTableView *ccMetaTableView;
}
- (void)setMode: (int)mode;
- (int)mode;
- (void)select: (BOOL)flag forKey: (id)key;
- (BOOL)isSelectedForKey: (id)key;
- (id)ccMetaFilters;
- (void)addNewCCMetaFilter: (int)number selected: (BOOL)selected;

@end
