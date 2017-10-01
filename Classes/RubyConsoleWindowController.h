//
//  RubyConsoleWindowController.h
//  Alchemusica
//
//  Created by Toshi Nagata on 09/03/01.
//  Copyright 2009-2016 Toshi Nagata. All rights reserved.
//
/*
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import <Cocoa/Cocoa.h>

#define MAX_HISTORY_LINES 1000

@interface RubyConsoleWindowController : NSWindowController {
	IBOutlet NSTextView *consoleView;
	NSColor *defaultColor;

	//  History support
	char **valueHistory, **commandHistory;
	int nValueHistory, nCommandHistory;
	int valueHistoryIndex, commandHistoryIndex;
	int32_t historyPos;
	int32_t keyInputPos;
}
+ (RubyConsoleWindowController *)sharedRubyConsoleWindowController;

@end
