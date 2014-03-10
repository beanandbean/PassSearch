#import "PanelController.h"
#import "BackgroundView.h"
#import "StatusItemView.h"
#import "MenubarController.h"

#define OPEN_DURATION .15
#define CLOSE_DURATION .1

#define SEARCH_INSET 20

#define POPUP_HEIGHT 250
#define PANEL_WIDTH 350
#define MENU_ANIMATION_DURATION .1

typedef enum {
    ClosePanelCommandNormal,
    ClosePanelCommandQuit,
    ClosePanelCommandAdd,
    ClosePanelCommandEdit
} ClosePanelCommand;

#pragma mark -

@implementation PanelController

#pragma mark -

- (id)initWithDelegate:(id<PanelControllerDelegate>)delegate
{
    self = [super initWithWindowNibName:@"Panel"];
    if (self != nil)
    {
        _delegate = delegate;
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".passsearch.data"];
        if ([fileManager fileExistsAtPath:path]) {
            self.data = [NSMutableDictionary dictionaryWithContentsOfFile:path];
        } else {
            self.data = [NSMutableDictionary dictionary];
            [self saveData];
        }
        
        self.result = [[NSArrayController alloc] init];
        self.result.clearsFilterPredicateOnInsertion = NO;
        self.result.sortDescriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]];
        self.result.automaticallyRearrangesObjects = YES;
        [self.result addObjects:self.data.allKeys];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTextDidChangeNotification object:self.searchField];
}

#pragma mark -

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // Make a fully skinned panel
    NSPanel *panel = (id)[self window];
    [panel setAcceptsMouseMovedEvents:YES];
    [panel setLevel:NSPopUpMenuWindowLevel];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
    
    // Follow search string
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(runSearch) name:NSControlTextDidChangeNotification object:self.searchField];
}

#pragma mark - Public accessors

- (BOOL)hasActivePanel
{
    return _hasActivePanel;
}

- (void)setHasActivePanel:(BOOL)flag
{
    if (_hasActivePanel != flag)
    {
        _hasActivePanel = flag;
        
        if (_hasActivePanel)
        {
            [self openPanel];
        }
        else
        {
            [self closePanel:NO];
        }
    }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    self.hasActivePanel = NO;
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    if ([[self window] isVisible])
    {
        self.hasActivePanel = NO;
    }
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow *panel = [self window];
    NSRect statusRect = [self statusRectForWindow:panel];
    NSRect panelRect = [panel frame];
    
    CGFloat statusX = roundf(NSMidX(statusRect));
    CGFloat panelX = statusX - NSMinX(panelRect);
    
    self.backgroundView.arrowX = panelX;
    
    NSRect searchRect = [self.searchField frame];
    searchRect.size.width = NSWidth([self.backgroundView bounds]) - SEARCH_INSET * 2 - 93;
    searchRect.origin.x = SEARCH_INSET;
    searchRect.origin.y = NSHeight([self.backgroundView bounds]) - ARROW_HEIGHT - SEARCH_INSET - NSHeight(searchRect);
    [self.searchField setFrame:searchRect];
    
    NSRect addRect = [self.addButton frame];
    addRect.origin.y = searchRect.origin.y;
    addRect.size.height = searchRect.size.height;
    [self.addButton setFrame:addRect];
    
    NSRect quitRect = [self.quitButton frame];
    quitRect.origin.y = searchRect.origin.y;
    quitRect.size.height = searchRect.size.height;
    [self.quitButton setFrame:quitRect];
    
    NSRect scrollRect = [self.resultScroll frame];
    scrollRect.size.height = NSHeight([self.backgroundView bounds]) - SEARCH_INSET * 2 - ARROW_HEIGHT - 30;
    scrollRect.origin.y = SEARCH_INSET;
    [self.resultScroll setFrame:scrollRect];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [self.result.arrangedObjects count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"result"]) {
        return [self.result.arrangedObjects objectAtIndex:row];
    } else if ([tableColumn.identifier isEqualToString:@"edit"]) {
        return [NSImage imageNamed:@"Edit"];
    } else {
        return nil;
    }
}

#pragma mark - NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    int column = (int)[self.resultTable columnAtPoint:[self.resultTable convertPoint:[self.window convertScreenToBase:[NSEvent mouseLocation]] fromView:nil]];
    if (column == 0) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        NSString *password = [self decrypt:[self.data objectForKey:[self.result.arrangedObjects objectAtIndex:row]]];
        [pasteboard writeObjects:[NSArray arrayWithObject:password]];
        [self.delegate togglePanel:self];
        return YES;
    } else if (column == 1) {
        [self startAlertAtRow:(int)row];
        return NO;
    } else {
        return NO;
    }
}

#pragma mark - Keyboard

- (void)cancelOperation:(id)sender
{
    self.hasActivePanel = NO;
}

- (void)runSearch
{
    NSString *searchString = [self.searchField stringValue];
    if (searchString.length) {
        NSArray *keywords = [searchString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *queries = [NSMutableArray array];
        NSMutableArray *args = [NSMutableArray array];
        for (NSString *keyword in keywords) {
            if (keyword.length) {
                [queries addObject:@"(self contains[c] %@)"];
                [args addObject:keyword];
            }
        }
        if (queries.count) {
            NSString *query = [queries componentsJoinedByString:@"&&"];
            [self.result setFilterPredicate:[NSPredicate predicateWithFormat:query argumentArray:args]];
        } else {
            [self.result setFilterPredicate:nil];
        }
    } else {
        [self.result setFilterPredicate:nil];
    }
    [self.resultTable reloadData];
}

#pragma mark - Public methods

- (NSRect)statusRectForWindow:(NSWindow *)window
{
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = NSZeroRect;
    
    StatusItemView *statusItemView = nil;
    if ([self.delegate respondsToSelector:@selector(statusItemViewForPanelController:)])
    {
        statusItemView = [self.delegate statusItemViewForPanelController:self];
    }
    
    if (statusItemView)
    {
        statusRect = statusItemView.globalRect;
        statusRect.origin.y = NSMinY(statusRect) - NSHeight(statusRect);
    }
    else
    {
        statusRect.size = NSMakeSize(STATUS_ITEM_VIEW_WIDTH, [[NSStatusBar systemStatusBar] thickness]);
        statusRect.origin.x = roundf((NSWidth(screenRect) - NSWidth(statusRect)) / 2);
        statusRect.origin.y = NSHeight(screenRect) - NSHeight(statusRect) * 2;
    }
    return statusRect;
}

- (void)openPanel
{
    NSWindow *panel = [self window];
    
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = [self statusRectForWindow:panel];

    NSRect panelRect = [panel frame];
    panelRect.size.width = PANEL_WIDTH;
    panelRect.size.height = POPUP_HEIGHT;
    panelRect.origin.x = roundf(NSMidX(statusRect) - NSWidth(panelRect) / 2);
    panelRect.origin.y = NSMaxY(statusRect) - NSHeight(panelRect);
    
    if (NSMaxX(panelRect) > (NSMaxX(screenRect) - ARROW_HEIGHT))
        panelRect.origin.x -= NSMaxX(panelRect) - (NSMaxX(screenRect) - ARROW_HEIGHT);
    
    [NSApp activateIgnoringOtherApps:NO];
    [panel setAlphaValue:0];
    [panel setFrame:statusRect display:YES];
    [panel makeKeyAndOrderFront:nil];
    
    [self.resultTable reloadData];
    [self.resultTable deselectAll:self];
    
    NSTimeInterval openDuration = OPEN_DURATION;
    
    NSEvent *currentEvent = [NSApp currentEvent];
    if ([currentEvent type] == NSLeftMouseDown)
    {
        NSUInteger clearFlags = ([currentEvent modifierFlags] & NSDeviceIndependentModifierFlagsMask);
        BOOL shiftPressed = (clearFlags == NSShiftKeyMask);
        BOOL shiftOptionPressed = (clearFlags == (NSShiftKeyMask | NSAlternateKeyMask));
        if (shiftPressed || shiftOptionPressed)
        {
            openDuration *= 10;
            
            if (shiftOptionPressed)
                NSLog(@"Icon is at %@\n\tMenu is on screen %@\n\tWill be animated to %@",
                      NSStringFromRect(statusRect), NSStringFromRect(screenRect), NSStringFromRect(panelRect));
        }
    }
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:openDuration];
    [[panel animator] setFrame:panelRect display:YES];
    [[panel animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
    
    [panel performSelector:@selector(makeFirstResponder:) withObject:self.searchField afterDelay:openDuration];
}

- (void)closePanel:(BOOL)quit;
{
    self.searchField.stringValue = @"";
    [self.result setFilterPredicate:nil];
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:CLOSE_DURATION];
    [[[self window] animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];
    
    dispatch_after(dispatch_walltime(NULL, NSEC_PER_SEC * CLOSE_DURATION * 2), dispatch_get_main_queue(), ^{
        
        [self.window orderOut:nil];
        
        if (quit) {
            [[NSApplication sharedApplication] terminate:nil];
        }
    });
}

- (IBAction)add:(id)sender {
    [self startAlertAtRow:-1];
}

- (IBAction)quit:(id)sender {
    [self closePanel:YES];
}

- (void)startAlertAtRow:(int)row {
    NSString *message;
    NSString *info;
    NSString *defaultButton;
    NSString *otherButton;
    if (row == -1) {
        message = @"Add new entry";
        info = @"Please enter the entry memo and password";
        defaultButton = @"Add";
        otherButton = nil;
    } else {
        message = @"Edit entry";
        info = @"You can edit the entry memo and password";
        defaultButton = @"Update";
        otherButton = @"Remove";
    }
    NSAlert *alert = [NSAlert alertWithMessageText:message defaultButton:defaultButton alternateButton:@"Cancel" otherButton:otherButton informativeTextWithFormat:@"%@", info];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 270, 58)];
    NSTextView *memoLabel = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 40, 70, 12)];
    memoLabel.backgroundColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0];
    [memoLabel insertText:@"Memo:"];
    [memoLabel setEditable:NO];
    [view addSubview:memoLabel];
    NSTextField *memo = [[NSTextField alloc] initWithFrame:NSMakeRect(70, 34, 200, 24)];
    [view addSubview:memo];
    NSTextView *passwordLabel = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 6, 70, 12)];
    passwordLabel.backgroundColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0];
    [passwordLabel insertText:@"Password:"];
    [passwordLabel setEditable:NO];
    [view addSubview:passwordLabel];
    NSTextField *password = [[NSTextField alloc] initWithFrame:NSMakeRect(70, 0, 200, 24)];
    [view addSubview:password];
    NSString *memoStr;
    if (row != -1) {
        memoStr = [self.result.arrangedObjects objectAtIndex:row];
        memo.stringValue = memoStr;
        password.stringValue = [self decrypt:[self.data objectForKey:memoStr]];
    }
    [alert setAccessoryView:view];
    NSInteger button = [alert runModal];
    if (button == NSAlertDefaultReturn) {
        NSString *task;
        if (row == -1) {
            task = @"add";
        } else {
            task = @"update";
        }
        if (!memo.stringValue.length) {
            [[NSAlert alertWithMessageText:message defaultButton:@"Okay" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Cannot %@ entry: Memo is left blank!", task] runModal];
        } else if (!password.stringValue.length) {
            [[NSAlert alertWithMessageText:message defaultButton:@"Okay" alternateButton:nil otherButton:nil informativeTextWithFormat:@"Cannot %@ entry: Password is left blank!", task] runModal];
        } else if (row != -1 && [memo.stringValue isEqualToString:memoStr]) {
            [self.data setObject:[self encrypt:password.stringValue] forKey:memoStr];
            [self saveData];
        } else if ([self.data objectForKey:memo.stringValue]) {
            NSInteger choice = [[NSAlert alertWithMessageText:message defaultButton:@"Override" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"Memo already exist!"] runModal];
            if (choice == NSAlertDefaultReturn) {
                if (row != -1) {
                    [self.data removeObjectForKey:memoStr];
                    [self.result removeObject:memoStr];
                }
                [self.data setObject:[self encrypt:password.stringValue] forKey:memo.stringValue];
                [self saveData];
            }
        } else {
            if (row != -1) {
                [self.data removeObjectForKey:memoStr];
                [self.result removeObject:memoStr];
            }
            [self.data setObject:[self encrypt:password.stringValue] forKey:memo.stringValue];
            [self.result addObject:memo.stringValue];
            [self saveData];
        }
    } else if (button == NSAlertOtherReturn) {
        [self.data removeObjectForKey:memoStr];
        [self.result removeObject:memoStr];
        [self saveData];

    }
    [self.delegate togglePanel:self];
}

- (void)saveData {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".passsearch.data"];
    [self.data writeToFile:path atomically:NO];
}

- (NSString *)encrypt:(NSString *)string {
    return [[string dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

- (NSString *)decrypt:(NSString *)string {
    return [[NSString alloc] initWithData:[[NSData alloc] initWithBase64EncodedString:string options:0] encoding:NSUTF8StringEncoding];
}

@end
