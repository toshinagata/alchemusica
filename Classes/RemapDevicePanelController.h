//
//  RemapDevicePanelCotroller.h
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

@class MyDocument;

@interface RemapDevicePanelController : NSWindowController <NSTableViewDataSource>
{
	IBOutlet id myTableView;
	BOOL stopModalFlag;
	MyDocument *myDocument;
    NSArray *myTrackSelection;
	NSMutableArray *deviceNumbers;	//  The device number (index of currentValues) for each track
	NSMutableArray *initialValues;
	NSMutableArray *currentValues;
}
- (id)initWithDocument: (MyDocument *)document trackSelection: (NSArray *)trackSelection;
- (void)beginSheetForWindow: (NSWindow *)parentWindow invokeStopModalWhenDone: (BOOL)flag;
- (IBAction)changeAction:(id)sender;
- (IBAction)dontChangeAction:(id)sender;


@end
