//
//  MyAppController.m
//
//  Created by Toshi Nagata.
/*
    Copyright (c) 2000-2016 Toshi Nagata. All rights reserved.

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation version 2 of the License.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 */

#import "MyAppController.h"
#import "MyDocument.h"
#import "LoadingPanelController.h"
#import "RubyConsoleWindowController.h"
#import "AudioSettingsPanelController.h"
#import "MetronomeSettingsPanelController.h"
#import "AboutWindowController.h"

#include "MDHeaders.h"
#include "MDRubyExtern.h"

NSString *MyAppScriptMenuModifiedNotification = @"Script menu modified";
NSString *MyAppControllerMIDISetupDidChangeNotification = @"MIDI setup changed";
NSString *MyAppControllerModalPanelTimerNotification = @"Modal Panel timer fired";

static int sScriptMenuCount = 0;

@implementation MyAppController

//  起動時に空のウィンドウを開かないようにする
//- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
//     return NO;
//}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter]
        removeObserver:self];
	[super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	[AboutWindowController showSplashWindow];
	
	//  Initialize Audio/MIDI devices
	MDAudioInitialize();

	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(updateScriptMenu:)
		name:MyAppScriptMenuModifiedNotification
		object:self];

	scriptMenuInfos = [[NSMutableArray array] retain];
	sScriptMenuCount = [scriptMenu numberOfItems];
	
	{
		int i;

		//  Load Ruby console window (initially invisible)
		[[[RubyConsoleWindowController sharedRubyConsoleWindowController] window] orderOut: self];
		
		//  Initialize MDRuby
		Ruby_startup();
		
		//  MDRuby startup scripts
		//  (Executed in alphabetical order)
		NSFileManager *manager = [NSFileManager defaultManager];
		int status = 0;
		NSString *pluginDir = [[[NSBundle mainBundle] builtInPlugInsPath] stringByAppendingPathComponent: @"Ruby_Scripts"];
		NSString *cwd = [manager currentDirectoryPath];
		NSArray *scriptArray = [[manager directoryContentsAtPath: pluginDir] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
		[manager changeCurrentDirectoryPath: pluginDir];
		for (i = 0; i < [scriptArray count]; i++) {
			const char *s = [[scriptArray objectAtIndex: i] UTF8String];
			if (s == NULL)
				continue;
			MyAppCallback_showScriptMessage("Loading %s...\n", s);
			MyAppCallback_executeScriptFromFile(s, &status);
			if (status != 0) {
				Ruby_showError(status);
				break;
			}
		}
		if (status == 0)
			MyAppCallback_showScriptMessage("Done.\n");
		MyAppCallback_showRubyPrompt();
		[manager changeCurrentDirectoryPath: cwd];
	}
	
	[MetronomeSettingsPanelController initializeMetronomeSettings];

	[AboutWindowController hideSplashWindow];

}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	MDAudioDispose();
	MyAppCallback_saveGlobalSettings();
}

static void
appendScriptMenuItems(NSMenu *menu, NSArray *infos, SEL action, id target)
{
	int i, n;
	n = [infos count];
	for (i = 0; i < n; i++) {
		id obj = [infos objectAtIndex: i];
		id item = [menu insertItemWithTitle: @"X" action: action keyEquivalent: @"" atIndex: i];
		[item setTitle: [obj valueForKey: @"title"]];
		[item setTag: i];
		[item setTarget: target];
	}
}

- (void)registerScriptMenu: (NSString *)commandName withTitle: (NSString *)menuTitle
{
	int i, n;
	n = [scriptMenuInfos count];
	for (i = 0; i < n; i++) {
		id obj = [scriptMenuInfos objectAtIndex: i];
		if ([commandName isEqualToString: [obj valueForKey: @"command"]]) {
			[obj setValue: menuTitle forKey: @"title"];
			break;
		} else if ([menuTitle isEqualToString: [obj valueForKey: @"title"]]) {
			[obj setValue: commandName forKey: @"command"];
			break;
		}
	}
	if (i >= n) {
		[scriptMenuInfos addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
			commandName, @"command", menuTitle, @"title",
			nil]];
	}
	
	//  Post notification (processed only once per event loop)
	[[NSNotificationQueue defaultQueue]
		enqueueNotification:
			[NSNotification notificationWithName: MyAppScriptMenuModifiedNotification object: self]
		postingStyle: NSPostWhenIdle
		coalesceMask: NSNotificationCoalescingOnName | NSNotificationCoalescingOnSender
		forModes: nil];
}

- (void)updateScriptMenu: (NSNotification *)aNotification
{
	while ([scriptMenu numberOfItems] > sScriptMenuCount) {
		[scriptMenu removeItemAtIndex: sScriptMenuCount];
	}
	if ([scriptMenuInfos count] > 0) {
		[scriptMenu addItem:[NSMenuItem separatorItem]];
		appendScriptMenuItems(scriptMenu, scriptMenuInfos, @selector(doScriptCommand:), self);
	}
}

- (IBAction)executeRubyScriptFromFile: (id)sender
{
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	int status;
	NSArray *filenames;
	NSString *filename;
	NSMutableString *script;
	[panel setMessage: @"Choose Ruby script file"];
	status = [panel runModalForTypes: [NSArray arrayWithObjects: @"rb", nil]];
	filenames = [panel filenames];
	[panel close];
	if (status != NSOKButton)
		return;
	filename = [filenames objectAtIndex: 0];

	//  Show command line in the Ruby console
	script = [NSMutableString stringWithString: filename];
	[script replaceOccurrencesOfString: @"\\" withString: @"\\\\" options: 0 range: NSMakeRange(0, [script length])]; //  backslash
	[script replaceOccurrencesOfString: @"'" withString: @"\\'" options: 0 range: NSMakeRange(0, [script length])]; //  single quote
	MyAppCallback_setConsoleColor(1);
	MyAppCallback_showScriptMessage("execute_script('%s')\n", [script UTF8String]);
	MyAppCallback_setConsoleColor(0);

	//  Execute file
	MyAppCallback_executeScriptFromFile([filename UTF8String], &status);
	if (status != 0)
		Ruby_showError(status);
}

- (IBAction)openRubyConsole: (id)sender
{
	[[[RubyConsoleWindowController sharedRubyConsoleWindowController] window] makeKeyAndOrderFront: self];
}

//  Invoke Ruby command. If the command is a singleton method of the Sequence class, then
//  the command is invoked with the document as the single argument (if document == nil, then
//  with Qnil as the argument). Otherwise, the command should be a method of Sequence class,
//  and the method is invoked with the document as self.
- (void)performScriptCommand: (NSString *)command forDocument: (MyDocument *)document
{
	int kind, status;
	const char *cmd = [command UTF8String];
	kind = Ruby_methodType("Sequence", cmd);
	if (kind != 1 && kind != 2) {
		[[NSAlert alertWithMessageText: @"Undefined Command" defaultButton: nil alternateButton: nil otherButton: nil informativeTextWithFormat: @"The requested command %s is not defined.", cmd] runModal];
		return;
	}
	status = Ruby_callMethodOfDocument(cmd, document, kind == 2, NULL);
	if (status != 0) {
		Ruby_showError(status);
		return;
	}
}

//  Check if the command is valid as the script menu command.
//  If "validate_..." method is defined, that method is called (with the same arguments 
//  as the menu command), and the menu is validated if the return value is true.
//  Otherwise, if the method is a Sequence class method, the menu is always validated.
//  Otherwise, the menu is validated if there is an active document.
- (BOOL)validateScriptCommand: (NSString *)command forDocument: (MyDocument *)document
{
	int kind, status;
	const char *cmd = [[NSString stringWithFormat: @"validate_%@", command] UTF8String];
	kind = Ruby_methodType("Sequence", cmd);
	if (kind == 1 || kind == 2) {
		unsigned char bval;
		status = Ruby_callMethodOfDocument(cmd, document, kind == 2, ";b", &bval);
		if (status == 0 && bval)
			return YES;
		else return NO;
	}
	cmd = [command UTF8String];
	kind = Ruby_methodType("Sequence", cmd);
	if (kind == 2)
		return YES;
	if (kind == 1 && document != nil)
		return YES;
	return NO;
}

- (void)doScriptCommand: (id)sender
{
	int i, n;
	NSString *title = [sender title];
	n = [scriptMenuInfos count];
	for (i = 0; i < n; i++) {
		id obj = [scriptMenuInfos objectAtIndex: i];
		if ([title isEqualToString: [obj valueForKey: @"title"]]) {
			//  Menu command found
			[self performScriptCommand: [obj valueForKey: @"command"] forDocument: (MyDocument *)[self documentAtIndex: 0]];
			return;
		}
	}
}

- (IBAction)openAudioSettingsPanel: (id)sender
{
	[AudioSettingsPanelController openAudioSettingsPanel];
}

- (IBAction)openMetronomeSettingsPanel: (id)sender
{
	[MetronomeSettingsPanelController openMetronomeSettingsPanel];
}

- (IBAction)openAboutWindow:(id)sender
{
	[AboutWindowController showModalAboutWindow];
}

- (IBAction)updateAudioAndMIDISettings:(id)sender
{
	MDAudioUpdateDeviceInfo();
	MDPlayerReloadDeviceInformation();
}

- (BOOL)validateUserInterfaceItem: (id)anItem
{
	SEL sel = [anItem action];
	if (sel == @selector(doScriptCommand:)) {
		int i, n;
		NSString *title = [anItem title];
		n = [scriptMenuInfos count];
		for (i = 0; i < n; i++) {
			id obj = [scriptMenuInfos objectAtIndex: i];
			if ([title isEqualToString: [obj valueForKey: @"title"]]) {
				//  Menu command found
				return [self validateScriptCommand: [obj valueForKey: @"command"] forDocument: (MyDocument *)[self documentAtIndex: 0]];
			}
		}
		return NO;
	}
	return YES;
}

- (id)documentAtIndex: (int)idx
{
	id documents = [NSApp orderedDocuments];
	if (documents == nil || idx < 0 || idx >= [documents count])
		return nil;
	return [documents objectAtIndex: idx];
}

#pragma mark ====== Ruby Progress Panel Support ======

- (BOOL)showProgressPanel: (NSString *)caption
{
	if (rubyProgressPanelController != nil)
		return NO;  /*  Nested call  */
	rubyProgressPanelController = [[LoadingPanelController alloc] initWithTitle: @"MDRuby Progress" andCaption: caption];
	[rubyProgressPanelController beginSession];
	return YES;
}

- (void)hideProgressPanel
{
	if (rubyProgressPanelController == nil)
		return;
	[rubyProgressPanelController endSession];
	[rubyProgressPanelController close];
	[rubyProgressPanelController autorelease];
	rubyProgressPanelController = nil;
}

- (void)setProgressValue: (double)dval
{
	[rubyProgressPanelController setProgressValue: dval * 100.0];
}

- (void)setProgressMessage: (NSString *)caption
{
	[rubyProgressPanelController setCaption: caption];
}

- (BOOL)checkInterrupt
{
	NSEvent *event;
	NSString *s;
	unsigned int flags;
	if (rubyProgressPanelController != nil) {
		if (![rubyProgressPanelController runSession] || [rubyProgressPanelController canceled])
			return YES;
		else return NO;
	} else {
		while (nil != (event = [NSApp nextEventMatchingMask: NSAnyEventMask untilDate: nil inMode: NSEventTrackingRunLoopMode dequeue: YES])) {
			if ([event type] == NSKeyDown) {
				s = [event charactersIgnoringModifiers];
				flags = [event modifierFlags];
				if ([s isEqualToString: @"."] && (flags & NSCommandKeyMask) != 0) {
					return YES;
				} else {
					NSBeep();
					return NO;
				}
			}
		}
		return NO;
	}
}

- (void)getRubyVersion:(NSString **)outVersion copyright:(NSString **)outCopyright
{
	const char *version, *copyright;
	Ruby_getVersionStrings(&version, &copyright);
	if (outVersion != NULL)
		*outVersion = [NSString stringWithUTF8String:version];
	if (outCopyright != NULL)
		*outCopyright = [NSString stringWithUTF8String:copyright];
}

- (void)getVersion:(NSString **)outVersion copyright:(NSString **)outCopyright lastBuild:(NSString **)outLastBuild revision:(int *)outRevision
{
	NSMutableData *data = [NSMutableData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource: @"Version" ofType: nil]];
	char *p1, *p2;
	char *p;
	NSString *version, *copyright, *lastBuild;
	version = copyright = lastBuild = nil;
	if (data != nil) {
		p = [data mutableBytes];
		if ((p1 = strstr(p, "version")) != NULL) {
			p1 = strchr(p1, '\"');
			if (p1 != NULL) {
				p1++;
				p2 = strchr(p1, '\"');
				if (p2 != NULL) {
					*p2 = 0;
					version = [NSString stringWithUTF8String:p1];
					*p2 = '\"';
				}
			}
		}
		if ((p1 = strstr(p, "date")) != NULL) {
			/*  Release date  */
			p1 = strchr(p1, '\"');
			if (p1 != NULL) {
				p1++;
				p2 = strchr(p1, '\"');
				if (p2 != NULL) {
					*p2 = 0;
					if (strlen(p1) > 4) {
						copyright = [NSString stringWithFormat:@"2000-%.4s", p1];
					}
					*p2 = '\"';
				}
			}
		}
	}
	data = [NSMutableData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource: @"lastBuild.txt" ofType: nil]];
	if (data != nil) {
		p = [data mutableBytes];
		if ((p1 = strstr(p, "last_build")) != NULL) {
			p1 = strchr(p1, '\"');
			if (p1 != NULL) {
				p1++;
				p2 = strchr(p1, '\"');
				if (p2 != NULL) {
					*p2 = 0;
					lastBuild = [NSString stringWithUTF8String:p1];
					*p2 = '\"';
				}
			}
		}
		if ((p1 = strstr(p, "svn_revision =")) != NULL) {
			p1 = p1 + 14;
			if (outRevision != NULL)
				*outRevision = strtol(p1, NULL, 0);
		}		
	}
	if (outVersion != NULL)
		*outVersion = version;
	if (outCopyright != NULL)
		*outCopyright = copyright;
	if (outLastBuild != NULL)
		*outLastBuild = lastBuild;
}

@end

#pragma mark ====== Plain-C interface ======

static NSMutableDictionary *sGlobalSettings = nil;

void
MyAppCallback_loadGlobalSettings(void)
{
	/*  Do nothing  */
}

void
MyAppCallback_saveGlobalSettings(void)
{
	if (sGlobalSettings != nil) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults setValue:sGlobalSettings forKey:@"settings"];
		[defaults synchronize];
	}
}

id
MyAppCallback_getObjectGlobalSettings(id keyPath)
{
	if (sGlobalSettings == nil) {
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		sGlobalSettings = [defaults valueForKey:@"settings"];
		if (sGlobalSettings == nil) {
			sGlobalSettings = [[NSMutableDictionary alloc] init];
			[defaults setValue:sGlobalSettings forKey:@"settings"];
		}
	}
	if (keyPath != nil)
		return [sGlobalSettings valueForKeyPath:keyPath];
	else return nil;
}

void
MyAppCallback_setObjectGlobalSettings(id keyPath, id value)
{
	id dic, obj, key;
	const char *p, *pp;
	p = [keyPath UTF8String];
	if (sGlobalSettings == nil)
		obj = MyAppCallback_getObjectGlobalSettings(nil);  /*  Initialize sGlobalSettings  */
	dic = key = nil;
	obj = sGlobalSettings;
	while ((pp = strchr(p, '.')) != NULL) {
		key = [NSString stringWithFormat:@"%.*s", (int)(pp - p), p];
		dic = obj;
		obj = [dic valueForKey:key];
		if (obj == nil) {
			obj = [NSMutableDictionary dictionary];
			[dic setValue:obj forKey:key];
		}
		p = pp + 1;
	}
	/*  Set the given object  */
	/*  If the container (= obj) is not mutable, then make it mutable  */
	if (dic != nil && ![obj isKindOfClass:[NSMutableDictionary class]]) {
		obj = [NSMutableDictionary dictionaryWithDictionary:obj];
		[dic setValue:obj forKey:key];
	}
	key = [NSString stringWithUTF8String:p];
	[obj setValue:value forKey:key];
}

const char *
MyAppCallback_getGlobalSettings(const char *key)
{
	id obj = MyAppCallback_getObjectGlobalSettings([NSString stringWithUTF8String:key]);
	if (obj != nil) {
		if (![obj isKindOfClass:[NSString class]])
			obj = [obj description];
		return [obj UTF8String];
	}
	else return NULL;
}

void
MyAppCallback_setGlobalSettings(const char *key, const char *value)
{
	MyAppCallback_setObjectGlobalSettings([NSString stringWithUTF8String:key], [NSString stringWithUTF8String:value]);
}

void
MyAppCallback_registerScriptMenu(const char *cmd, const char *title)
{
	MyAppController *cont = (MyAppController *)[NSApp delegate];
	[cont registerScriptMenu: [NSString stringWithUTF8String: cmd] withTitle: [NSString stringWithUTF8String: title]];
}

RubyValue
MyAppCallback_executeScriptFromFile(const char *cpath, int *status)
{
	RubyValue retval;
	NSString *fullpath, *cwd, *dir;
	NSString *contents;
	NSFileManager *manager = [NSFileManager defaultManager];

	/*  Standardizing the path  */
	fullpath = [NSString stringWithUTF8String: cpath];
	cwd = [manager currentDirectoryPath];
	if (cpath[0] != '/' && cpath[0] != '~')
		fullpath = [NSString stringWithFormat: @"%@/%@", cwd, fullpath];
	fullpath = [fullpath stringByStandardizingPath];
	
	/*  Move to the directory  */
	dir = [fullpath stringByDeletingLastPathComponent];
	[manager changeCurrentDirectoryPath: dir];

	/*  Read the contents of the file  */
	contents = [NSString stringWithContentsOfFile: fullpath encoding: NSUTF8StringEncoding error: NULL];

	/*  Execute as a ruby script  */
	retval = Ruby_evalRubyScriptOnDocument([contents UTF8String], [[NSApp delegate] documentAtIndex: 0], status);

	/*  Restore the current directory  */
	[manager changeCurrentDirectoryPath: cwd];
	
	return retval;
}

int
MyAppCallback_checkInterrupt(void)
{
	MyAppController *cont = (MyAppController *)[NSApp delegate];
	if (cont == nil)
		return 0;
	return [cont checkInterrupt];
}

int
MyAppCallback_showProgressPanel(const char *msg)
{
	MyAppController *cont = (MyAppController *)[NSApp delegate];
	if (cont == nil)
		return 0;
	if (msg == NULL)
		msg = "Processing...";
	return [cont showProgressPanel: [NSString stringWithUTF8String: msg]];
}

void
MyAppCallback_hideProgressPanel(void)
{
	MyAppController *cont = (MyAppController *)[NSApp delegate];
	[cont hideProgressPanel];
}

void
MyAppCallback_setProgressValue(double dval)
{
	MyAppController *cont = (MyAppController *)[NSApp delegate];
	[cont setProgressValue: dval];
}

void
MyAppCallback_setProgressMessage(const char *msg)
{
	MyAppController *cont = (MyAppController *)[NSApp delegate];
	[cont setProgressMessage: [NSString stringWithUTF8String: msg]];
}

int
MyAppCallback_messageBox(const char *message, const char *title, int flags, int icon)
{
	NSString *btn1, *btn2;
	NSAlert *alert;
	int retval;
	switch (flags & 3) {
		case 0: case 1: btn1 = btn2 = nil; break;
		case 2: btn1 = @"Cancel"; btn2 = nil; break;
		case 3: btn1 = nil; btn2 = @"Cancel"; break;
	}
	alert = [NSAlert alertWithMessageText:[NSString stringWithUTF8String:title] defaultButton:btn1 alternateButton:btn2 otherButton:nil informativeTextWithFormat:@"%s", message];
	retval = [alert runModal];
	if (flags & 3 == 3)
		return (retval == NSAlertDefaultReturn);
	else return 1;  /*  Always OK, even if the message is "Cancel"  */
}

void
MyAppCallback_startupMessage(const char *message, ...)
{
	char *msg;
	va_list ap;
	va_start(ap, message);
	if (message != NULL)
		vasprintf(&msg, message, ap);
	else msg = NULL;
	[AboutWindowController setMessage:(msg == NULL ? nil : [NSString stringWithUTF8String:msg])];
	if (msg != NULL)
		free(msg);
}

#pragma mark ====== MIDI setup change notification ======

void
MDPlayerNotificationCallback(void)
{
	MDPlayerReloadDeviceInformation();
	[[NSNotificationCenter defaultCenter]
		postNotificationName: MyAppControllerMIDISetupDidChangeNotification
		object: [NSApp delegate] userInfo: nil];
}

