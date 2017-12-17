//
//  AUViewWindowController.m
//  Alchemusica
//
//  Created by Toshi Nagata on 10/06/26.
//  Copyright 2010-2016 Toshi Nagata. All rights reserved.
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

#import "AUViewWindowController.h"

#if USE_CARBON
#import <Carbon/Carbon.h>
#endif

#import <CoreAudioKit/CoreAudioKit.h>
#import <AudioUnit/AUCocoaUIView.h>

#if USE_CARBON
// Carbon event handler.
static OSStatus
sWindowEventHandler(EventHandlerCallRef myHandler, EventRef theEvent, void* userData)
{
	AUViewWindowController* cont = (AUViewWindowController *)userData;
	UInt32      eventKind = GetEventKind(theEvent);
	OSStatus ret;
	if (cont->isProcessingCarbonEventHandler)
		return eventNotHandledErr;
	cont->isProcessingCarbonEventHandler = YES;
	ret = eventNotHandledErr;
	switch (eventKind) {
		case kEventWindowActivated:
			[[cont window] makeKeyAndOrderFront: cont];
			ret = noErr;
			break;
		case kEventWindowClose:
			[cont close];
			[[[NSApp orderedWindows] objectAtIndex: 0] makeKeyWindow];
			ret = noErr;
			break;
	}
	cont->isProcessingCarbonEventHandler = NO;
	return ret;
}
#endif

@implementation AUViewWindowController

static NSMutableArray *sAUViewWindowControllers = nil;

+ (AUViewWindowController *)windowControllerForAudioUnit:(AudioUnit)unit cocoaView:(BOOL)cocoaView delegate:(id)delegate
{
	int i, n;
	id cont;
	if (sAUViewWindowControllers == nil) {
		sAUViewWindowControllers = [[NSMutableArray alloc] init];
	}
	n = (int)[sAUViewWindowControllers count];
	for (i = 0; i < n; i++) {
		cont = [sAUViewWindowControllers objectAtIndex: i];
		if ([cont audioUnit] == unit) {
			[[cont window] makeKeyAndOrderFront: nil];
			return cont;
		}
	}
	cont = [[[AUViewWindowController alloc] initWithAudioUnit:unit cocoaView:cocoaView delegate:delegate] autorelease];
	if (cont != nil) {
        //  The present implementation keeps the window controller even after
        //  the window is closed. This may hog the memory and CPU time. But
        //  releasing the Cocoa window sometimes caused crash, which
        //  I were not able to fix. So I will keep this way for a while.
        //  (Toshi Nagata 2017.10.8)
		[sAUViewWindowControllers addObject: cont];
		[[cont window] makeKeyAndOrderFront: nil];
	}
	return cont;
}

- (void)editWindowClosed
{
	// Any additional cocoa cleanup can be added here.
	[_delegate auViewWindowWillClose: self];
}

+ (BOOL)error:(NSString *)errString status:(OSStatus)err
{
	NSString *errorString = [NSString stringWithFormat:@"%@ failed with error code %i: %s", errString, (int)err, GetMacOSStatusCommentString(err)];
	NSLog(@"%@", errorString);
	return NO;
}

#if USE_CARBON
- (WindowRef)carbonWindowRef
{
	return carbonWindowRef;
}
#endif

- (AudioUnit)audioUnit
{
	return audioUnit;
}

/*
- (BOOL)installWindowCloseHandler
{
	EventTypeSpec eventList[] = {{kEventClassWindow, kEventWindowClose}};	
	EventHandlerUPP	handlerUPP = NewEventHandlerUPP(sWindowEventHandler);
	OSStatus err = InstallWindowEventHandler(carbonWindowRef, handlerUPP, 1, eventList, self, NULL);
	if (err != noErr) 
		return [self error: @"Installation of WindowClose handler" status: err];
	return YES;
}
*/

#if USE_CARBON
- (void)findUIViewComponentDescription:(BOOL)forceGeneric
{
	OSStatus err;
	UInt32 propSize;
	ComponentDescription *cds;

	// set up to use generic UI component
	viewCD.componentType = kAudioUnitCarbonViewComponentType;
	viewCD.componentSubType = 'gnrc';
	viewCD.componentManufacturer = 'appl';
	viewCD.componentFlags = 0;
	viewCD.componentFlagsMask = 0;
	
	if (forceGeneric)
		return;
	
	err = AudioUnitGetPropertyInfo(audioUnit, kAudioUnitProperty_GetUIComponentList, kAudioUnitScope_Global, 0, &propSize, NULL);
	
	if (err != noErr) {
		NSLog(@"Error setting up carbon interface, falling back to generic interface.");
		return;
	}
	
	cds = malloc(propSize);
	err = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_GetUIComponentList, kAudioUnitScope_Global, 0, cds, &propSize);
	
	if (err == noErr)
		viewCD = cds[0]; // Pick the first one
	
	free(cds);
}
#endif

+ (BOOL)pluginClassIsValid:(Class)pluginClass 
{
	if ([pluginClass conformsToProtocol: @protocol(AUCocoaUIBase)]) {
		if ([pluginClass instancesRespondToSelector: @selector(interfaceVersion)] &&
		    [pluginClass instancesRespondToSelector: @selector(uiViewForAudioUnit:withSize:)]) {
			return YES;
		}
	}
    return NO;
}

- (BOOL)hasCocoaView
{
	UInt32 dataSize = 0;
	Boolean isWritable = 0;
	OSStatus err = AudioUnitGetPropertyInfo(audioUnit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &dataSize, &isWritable);
	
	return (err == noErr && dataSize > 0);
}

+ (NSView *)getCocoaViewForAudioUnit:(AudioUnit)unit defaultViewSize:(NSSize)viewSize
{
	NSView *theView = nil;
	UInt32 dataSize = 0;
	Boolean isWritable = 0;
	OSStatus err = AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, &dataSize, &isWritable);
	
	if (err != noErr) {
        AUGenericView *aView = [[AUGenericView alloc] initWithAudioUnit:unit];
        if (aView == nil) {
            [self error: @"Cannot open cocoa view nor generic view" status: err];
            return nil;
        }
        return [aView autorelease];
	}
	
	AudioUnitCocoaViewInfo *cvi = malloc(dataSize);
	err = AudioUnitGetProperty(unit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0, cvi, &dataSize);
	
	unsigned numberOfClasses = (dataSize - sizeof(CFURLRef)) / sizeof(CFStringRef);
	NSString *viewClassName = (NSString *)(cvi->mCocoaAUViewClass[0]);
	NSString *path = [(NSURL *)(cvi->mCocoaAUViewBundleLocation) path];
	NSBundle *viewBundle = [NSBundle bundleWithPath:path];
	Class viewClass = [viewBundle classNamed:viewClassName];
	
	if ([AUViewWindowController pluginClassIsValid:viewClass]) {
		id factory = [[[viewClass alloc] init] autorelease];
		theView = [factory uiViewForAudioUnit:unit withSize:viewSize];
	}
	
	if (cvi != NULL) {
        int i;
        for (i = 0; i < numberOfClasses; i++)
            CFRelease(cvi->mCocoaAUViewClass[i]);
        CFRelease(cvi->mCocoaAUViewBundleLocation);
        free(cvi);
    }
	
	return theView;
}


- (NSView *)getCocoaView
{
    return [AUViewWindowController getCocoaViewForAudioUnit:audioUnit defaultViewSize:defaultViewSize];
}

#if USE_CARBON
-(NSWindow *)createCarbonWindow
{
	OSStatus res;
	Component editComponent = FindNextComponent(NULL, &viewCD);
	OpenAComponent(editComponent, &auCarbonView);
	if (auCarbonView == nil)
		[NSException raise:NSGenericException format:@"Could not open audio unit editor component"];
	
	Rect bounds = { 100, 100, 100, 100 }; // Generic resized later

	//  Load carbon window from the nib
	{
		IBNibRef nibRef;
		res = CreateNibReference(CFSTR("AUCarbonWindow"), &nibRef);
		if (res != noErr) {
			[[self class] error: @"Cannot load nib for carbon window" status: res];
			return nil;
		}
		res = CreateWindowFromNib(nibRef, CFSTR("Window"), &carbonWindowRef);
		if (res != noErr) {
			[[self class] error: @"Cannot load carbon window from nib" status: res];
			return nil;
		}
		DisposeNibReference(nibRef);
	}
	/* res = CreateNewWindow(kDocumentWindowClass, kWindowCloseBoxAttribute | kWindowCollapseBoxAttribute | kWindowStandardHandlerAttribute | kWindowCompositingAttribute, &bounds, &carbonWindowRef);
	if (res != noErr) {
		[self error:@"Creating new carbon window" status:res];
		return nil;
	} */
	
	ControlRef rootControl;
	res = GetRootControl(carbonWindowRef, &rootControl);
	if (rootControl == nil)  {
		[[self class] error:@"Getting root control of carbon window" status:res];
		return nil;
	}
	
	ControlRef viewPane;
	Float32Point loc  = { 0.0f, 0.0f };
	Float32Point size = { 0.0f, 0.0f } ;
	AudioUnitCarbonViewCreate(auCarbonView, audioUnit, carbonWindowRef, 
							  rootControl, &loc, &size, &viewPane);
	
	// resize and move window
	GetControlBounds(viewPane, &bounds);
	size.x = bounds.right - bounds.left;
	size.y = bounds.bottom - bounds.top;
	SizeWindow(carbonWindowRef, (short) (size.x + 0.5), (short) (size.y + 0.5),  true);
	RepositionWindow(carbonWindowRef, NULL, kWindowCenterOnMainScreen);

	//  Install event handler
	{
		EventTypeSpec eventList[] = {
			{kEventClassWindow, kEventWindowActivated},
		//	{kEventClassWindow, kEventWindowGetClickActivation},
			{kEventClassWindow, kEventWindowClose}
		};
		EventHandlerUPP	handlerUPP = NewEventHandlerUPP(sWindowEventHandler);
		res = InstallWindowEventHandler(carbonWindowRef, handlerUPP, sizeof(eventList) / sizeof(eventList[0]), eventList, self, NULL);
		if (res != noErr) {
			[[self class] error: @"Installation of WindowClose handler" status: res];
			return nil;
		}
	}
	
	return [[[NSWindow alloc] initWithWindowRef: carbonWindowRef] autorelease];
}
#endif

- (NSWindow *)createCocoaWindow
{
	if ([self hasCocoaView]) {
		NSView *res = [self getCocoaView];
		if (res) {
			 NSWindow *cocoaWindow = [[[NSWindow alloc] initWithContentRect: NSMakeRect(100, 400, [res frame].size.width, [res frame].size.height) styleMask: NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO] autorelease];
			[cocoaWindow setContentView:res];
			return cocoaWindow;
		}
	}
	return nil;
}

/*- (void)showWindow:(id)sender
{
	if (cocoaWindow)
		[super showWindow:sender];
	else if (carbonWindowRef)
		SelectWindow(carbonWindowRef);
}
*/

- (void)close
{
	[[self window] orderOut: self];
	[super close];
#if USE_CARBON
	if (carbonWindowRef) {
		DisposeWindow(carbonWindowRef);
		carbonWindowRef = 0;
	}
#endif
	[self editWindowClosed];
	[sAUViewWindowControllers removeObject: self];
}

- (id)initWithAudioUnit:(AudioUnit)unit cocoaView:(BOOL)cocoaView delegate:(id)delegate
{
	NSWindow *aWindow;

	self = [super initWithWindowNibName: @"AUViewWindow"];
	if (self == nil)
		return nil;

	audioUnit = unit;
	_delegate = delegate;
	defaultViewSize = NSMakeSize(400, 300);

#if USE_CARBON
	// We need to chack this in showWindow:
	carbonWindowRef = 0;
#endif

    if (cocoaView) {
        aWindow = [self createCocoaWindow];
    } else {
#if USE_CARBON
        [self findUIViewComponentDescription: NO];
		aWindow = [self createCarbonWindow];
#else
        aWindow = nil;
#endif
	}
    if (aWindow == nil) {
        [self release];
        return nil;
    }
    [self setWindow:aWindow];
    if ([aWindow delegate] == nil) {
        [aWindow setDelegate: self];
	}
	[[self window] makeKeyAndOrderFront: nil];
	return self;
}

@end
