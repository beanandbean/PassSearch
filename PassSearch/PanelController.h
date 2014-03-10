#import "BackgroundView.h"
#import "StatusItemView.h"

@class PanelController;

@protocol PanelControllerDelegate <NSObject>

@optional

- (StatusItemView *)statusItemViewForPanelController:(PanelController *)controller;

- (IBAction)togglePanel:(id)sender;

@end

#pragma mark -

@interface PanelController : NSWindowController <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
{
    BOOL _hasActivePanel;
}

@property (nonatomic, unsafe_unretained) IBOutlet BackgroundView *backgroundView;
@property (nonatomic, unsafe_unretained) IBOutlet NSSearchField *searchField;

@property (nonatomic) BOOL hasActivePanel;
@property (nonatomic, unsafe_unretained, readonly) id<PanelControllerDelegate> delegate;

@property (unsafe_unretained) IBOutlet NSButton *addButton;
@property (unsafe_unretained) IBOutlet NSButton *quitButton;
@property (unsafe_unretained) IBOutlet NSScrollView *resultScroll;
@property (unsafe_unretained) IBOutlet NSTableView *resultTable;

@property (strong) NSMutableDictionary *data;
@property (strong) NSArrayController *result;

- (id)initWithDelegate:(id<PanelControllerDelegate>)delegate;

- (IBAction)add:(id)sender;
- (IBAction)quit:(id)sender;

@end
