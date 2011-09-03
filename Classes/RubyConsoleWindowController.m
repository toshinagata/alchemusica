//
//  RubyConsoleWindowController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 09/03/01.
//  Copyright 2009-2011 Toshi Nagata. All rights reserved.
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

@implementation RubyConsoleWindowController

#pragma mark ====== Ruby Console ======

static RubyConsoleWindowController *shared;

+ (RubyConsoleWindowController *)sharedRubyConsoleWindowController
{
	if (shared == nil)
		shared = [[RubyConsoleWindowController alloc] initWithWindowNibName: @"RubyConsoleWindow"];
	return shared;
}

#if 0
#pragma mark ------ Unused ------
//  NSTextView delegate method
- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
	if (aSelector == @selector(insertNewline:)) {
		NSRange range;
		[aTextView insertNewline: self];
		range = [aTextView selectedRange];
		if (range.location + range.length >= [[aTextView textStorage] length]) {
			/*  Get the last line  */
			NSRange range2;
			NSString *str = [[aTextView textStorage] string];
			range.length = range.location - 1;
			range.location = 0;
			range2 = [str rangeOfString: @"\n" options: NSBackwardsSearch range: range];
			if (range2.location == NSNotFound)
				range2.location = 0;
			else range2.location++;
			range2.length = 1;
			if ([[str substringWithRange: range2] isEqualToString: @"%"])
				range2.location++;
			range2.length = range.length - range2.location + 1; /*  Include last newline  */
			str = [str substringWithRange: range2];
			
			{
				/*  Invoke Ruby interpreter  */
				VALUE val, script;
				int status;
				script = rb_str_new2([str UTF8String]);
				val = Ruby_CallMethodWithInterrupt(Qundef, 0, script, &status);
			/*	rb_protect(Ruby_EnableInterrupt, Qnil, &status2);
				val = rb_eval_string_protect([str UTF8String], &status);
				rb_protect(Ruby_DisableInterrupt, Qnil, &status2); */
				if (status == 0) {
					val = rb_protect(rb_inspect, val, &status);
					MyAppCallback_showScriptMessage("%s\n", StringValuePtr(val));
					[self showRubyPrompt];
				} else {
					MyAppCallback_showScriptError(status);
					/*  Next prompt is already shown here  */
				}
			}
		}
		return YES;
	}
	return NO;
}

- (IBAction)openRubyConsole: (id)sender
{
	[[consoleView window] makeKeyAndOrderFront: self];
}

- (IBAction)clearConsoleLog: (id)sender
{
	[consoleView setString: @""];
	[self showRubyPrompt];
}

#else

#pragma mark ------ Used ------

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
	range.length = len = [string length];
	if (color == nil)
		color = defaultColor;
	[consoleView setTextColor: color range: range];
	range.location += range.length;
	range.length = 0;
	[consoleView scrollRangeToVisible: range];
	return [string length];
}

- (int)appendMessage: (NSString *)string
{
	return [self appendMessage: string withColor: nil];
}

- (void)showRubyPrompt
{
	NSString *str = [[consoleView textStorage] string];
	int len = [str length];
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
	int strLen = [str length];

	//  Get the block of script to be executed
	range = [str lineRangeForRange: [[[consoleView selectedRanges] objectAtIndex: 0] rangeValue]];
	//  Look forwards
	end = range.location + range.length;
	while (end < strLen && [str characterAtIndex: end] == '>') {
		NSRange range1 = [str lineRangeForRange: NSMakeRange(end + 1, 0)];
		end = range1.location + range1.length;
	}
	//  Look backwards
	start = range.location;
	while (start > 0 && start < strLen && [str characterAtIndex: start] != '%') {
		NSRange range2 = [str lineRangeForRange: NSMakeRange(start - 1, 0)];
		start = range2.location;
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
	RubyValue val = Ruby_evalRubyScriptOnDocument([script UTF8String], [[NSApp delegate] documentAtIndex: 0], &status);

	defaultColor = [[NSColor redColor] retain];
	if (status != 0)
		Ruby_showError(status);
	else {
		[self appendMessage: @"-->"];
		Ruby_showRubyValue(val);
	}
	[defaultColor release];
	defaultColor = nil;
	[self showRubyPrompt];
	[consoleView setSelectedRange: NSMakeRange([[consoleView string] length], 0)];
}

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
	if (aSelector == @selector(insertNewline:)) {
		[self onEnterPressed: self];
		return YES;
	}
	return NO;
}

#endif

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

