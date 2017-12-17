//
//  RubyConsoleWindowController.m
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

#import "RubyConsoleWindowController.h"
#import "MyAppController.h"
#include "MDRubyExtern.h"
#include "MDHeaders.h"

@implementation RubyConsoleWindowController

#pragma mark ====== Ruby Console ======

static RubyConsoleWindowController *shared;

+ (RubyConsoleWindowController *)sharedRubyConsoleWindowController
{
	if (shared == nil)
		shared = [[RubyConsoleWindowController alloc] initWithWindowNibName: @"RubyConsoleWindow"];
	return shared;
}

- (void)windowDidLoad
{
	NSFont *font;
	[super windowDidLoad];
	font = [NSFont userFixedPitchFontOfSize:11.0f];
	[consoleView setFont:font];
    [consoleView setEnabledTextCheckingTypes:0];  //  Disable "smart=***"
}

- (void)flushMessage
{
	[consoleView display];
}

- (void)setConsoleColor: (int)colorID
{
	NSColor *col;
	switch (colorID) {
		case 1: col = [NSColor blueColor]; break;
		case 2: col = [NSColor greenColor]; break;
		case 4: col = [NSColor redColor]; break;
		default: col = nil; break;
	}
	[defaultColor release];
	defaultColor = col;
	if (col != nil)
		[col retain];
}

- (int)appendMessage: (NSString *)string withColor: (NSColor *)color
{
	NSRange range;
	int len;
	range.location = [[consoleView textStorage] length];
	range.length = 0;
	[consoleView replaceCharactersInRange: range withString: string];
	range.length = len = (int)[string length];
	if (color == nil)
		color = defaultColor;
	[consoleView setTextColor: color range: range];
	range.location += range.length;
	range.length = 0;
	[consoleView scrollRangeToVisible: range];
	return (int)[string length];
}

- (int)appendMessage: (NSString *)string
{
	return [self appendMessage: string withColor: nil];
}

- (void)showRubyPrompt
{
	NSString *str = [[consoleView textStorage] string];
	int len = (int)[str length];
	if (len > 0 && [str characterAtIndex: len - 1] != '\n')
		[self appendMessage: @"\n% "];
	else
		[self appendMessage: @"% "];
	[self flushMessage];
}

- (void)onEnterPressed: (id)sender
{
	//	printf("OnEnterPressed invoked\n");
	
//	if (::wxGetKeyState(WXK_ALT)) {
//		textCtrl->WriteText(wxT("\n> "));
//		return;
//	}
	NSString *str = [[consoleView textStorage] string];
	NSMutableString *script = [NSMutableString string];
	NSRange range, selectedLineRange;
	int start, end;
	int strLen = (int)[str length];

	//  Get the block of script to be executed
	range = [str lineRangeForRange: [[[consoleView selectedRanges] objectAtIndex: 0] rangeValue]];
	//  Look forwards
    end = (int)(range.location + range.length);
	while (end < strLen && [str characterAtIndex: end] == '>') {
		NSRange range1 = [str lineRangeForRange: NSMakeRange(end + 1, 0)];
        end = (int)(range1.location + range1.length);
	}
	//  Look backwards
	start = (int)range.location;
	while (start > 0 && start < strLen && [str characterAtIndex: start] != '%') {
		NSRange range2 = [str lineRangeForRange: NSMakeRange(start - 1, 0)];
		start = (int)range2.location;
	}
	if (start < strLen && [str characterAtIndex: start] == '%')
		start++;
	if (start < strLen && [str characterAtIndex: start] == ' ')
		start++;

	//  Get script (prompt characters are still in)
	selectedLineRange = NSMakeRange(start, end - start);
	script = [NSMutableString stringWithString: [str substringWithRange: selectedLineRange]];
	//  Remove prompt characters
	[script replaceOccurrencesOfString: @"\n>" withString: @"\n" options: 0 range: NSMakeRange(0, [script length])];
	[script replaceOccurrencesOfString: @"\n%" withString: @"\n" options: 0 range: NSMakeRange(0, [script length])];

	if ([script length] == 0) {
		//  Input is empty
		[self showRubyPrompt];
		return;
	}
	
	//  Append newline to avoid choking Ruby lexical analyzer
	if ([script characterAtIndex: [script length] - 1] != '\n')
		[script appendString: @"\n"];
		
	if (end < strLen) {
		// Enter is pressed in the block not at the end
		// -> Insert the text at the end
		[self showRubyPrompt];
		[self appendMessage: script withColor: [NSColor blueColor]];
	} else {
		[consoleView setTextColor: [NSColor blueColor] range: selectedLineRange];
		[self appendMessage: @"\n"];
	}
	
	//  Invoke ruby interpreter
	int status;
	char *cscript = strdup([script UTF8String]);
	RubyValue val = Ruby_evalRubyScriptOnDocument(cscript, [(MyAppController *)[NSApp delegate] documentAtIndex: 0], &status);
	cscript[strlen(cscript) - 1] = 0;  /*  Remove the last newline  */
	AssignArray(&commandHistory, &nCommandHistory, sizeof(char *), nCommandHistory, &cscript);
	if (nCommandHistory >= MAX_HISTORY_LINES)
		DeleteArray(&commandHistory, &nCommandHistory, sizeof(char *), 0, 1, NULL);
	defaultColor = [[NSColor redColor] retain];
	if (status != 0)
		Ruby_showError(status);
	else {
		char *valueString;
		[self appendMessage: @"-->"];
		status = Ruby_showValue(val, &valueString);
		if (status != 0) {
			Ruby_showError(status);
		} else {
			AssignArray(&valueHistory, &nValueHistory, sizeof(char *), nValueHistory, &valueString);
			if (nValueHistory >= MAX_HISTORY_LINES)
				DeleteArray(&valueHistory, &nValueHistory, sizeof(char *), 0, 1, NULL);
		}
	}
	[defaultColor release];
	defaultColor = nil;
	[self showRubyPrompt];
	[consoleView setSelectedRange: NSMakeRange([[consoleView string] length], 0)];
	commandHistoryIndex = valueHistoryIndex = -1;
}

- (BOOL)showHistory:(int)updown
{
	BOOL up = (updown < 0);
	BOOL option = ([[NSApp currentEvent] modifierFlags] & NSAlternateKeyMask) != 0;
	NSTextStorage *storage = [consoleView textStorage];
	char *p;
	if (commandHistoryIndex == -1 && valueHistoryIndex == -1) {
		if (!up)
			return NO;
		historyPos = (int)[storage length];
	}
	if (option) {
		if (up) {
			if (valueHistoryIndex == -1) {
				if (nValueHistory == 0)
					return NO;
				valueHistoryIndex = nValueHistory;
			}
			if (valueHistoryIndex <= 0)
				return YES; /* Key is processed but do nothing */
			valueHistoryIndex--;
			p = valueHistory[valueHistoryIndex];
		} else {
			if (valueHistoryIndex == -1)
				return YES;  /*  Do nothing  */
			if (valueHistoryIndex == nValueHistory - 1) {
				valueHistoryIndex = -1;
				p = "";
			} else {
				valueHistoryIndex++;
				p = valueHistory[valueHistoryIndex];
			}
		}
	} else {
		if (up) {
			if (commandHistoryIndex == -1) {
				if (nCommandHistory == 0)
					return NO;
				commandHistoryIndex = nCommandHistory;
			}
			if (commandHistoryIndex <= 0)
				return YES; /* Do nothing */
			commandHistoryIndex--;
			p = commandHistory[commandHistoryIndex];
		} else {
			if (commandHistoryIndex == -1)
				return YES;  /*  Do nothing  */
			if (commandHistoryIndex == nCommandHistory - 1) {
				commandHistoryIndex = -1;
				p = "";
			} else {
				commandHistoryIndex++;
				p = commandHistory[commandHistoryIndex];
			}
		}
	}
	if (p == NULL)
		p = "";
	[storage deleteCharactersInRange:NSMakeRange(historyPos, [storage length] - historyPos)];
	while (isspace(*p))
		p++;
	[self setConsoleColor:(option ? 4 : 1)];
	[self appendMessage:[NSString stringWithUTF8String:p]];
	[self setConsoleColor:0];
	return YES;
}

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
	if (aSelector == @selector(insertNewline:)) {
		[self onEnterPressed: self];
		return YES;
	} else if (aSelector == @selector(moveUp:) || aSelector == @selector(moveDown:)) {
		NSArray *a = [aTextView selectedRanges];
		NSRange r;
		if ([a count] == 1 && (r = [[a objectAtIndex:0] rangeValue]).length == 0 && r.location == [[aTextView textStorage] length])
			return [self showHistory:(aSelector == @selector(moveDown:) ? 1 : -1)];
		else return NO;
	}
	return NO;
}

@end

#pragma mark ====== Plain-C Interface ======

int
MyAppCallback_showScriptMessage(const char *fmt, ...)
{
	RubyConsoleWindowController *cont = [RubyConsoleWindowController sharedRubyConsoleWindowController];
	if (fmt != NULL) {
		char *p;
		va_list ap;
		int retval;
		va_start(ap, fmt);
		if (strchr(fmt, '%') == NULL) {
			/*  No format characters  */
			return [cont appendMessage: [NSString stringWithUTF8String: fmt]];
		} else if (strcmp(fmt, "%s") == 0) {
			/*  Direct output of one string  */
			p = va_arg(ap, char *);
			return [cont appendMessage: [NSString stringWithUTF8String: p]];
		}
		vasprintf(&p, fmt, ap);
		if (p != NULL) {
			retval = [cont appendMessage: [NSString stringWithUTF8String: p]];
			free(p);
			return retval;
		} else return 0;
	} else {
		[cont flushMessage];
		return 0;
	}
}

void
MyAppCallback_setConsoleColor(int color)
{
	RubyConsoleWindowController *cont = [RubyConsoleWindowController sharedRubyConsoleWindowController];
	[cont setConsoleColor: color];
}

void
MyAppCallback_showRubyPrompt(void)
{
	RubyConsoleWindowController *cont = [RubyConsoleWindowController sharedRubyConsoleWindowController];
	[cont setConsoleColor: 0];
	[cont showRubyPrompt];
}

