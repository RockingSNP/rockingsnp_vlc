/*****************************************************************************
 * VLCLibraryAlbumTableCellView.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2019 VLC authors and VideoLAN
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan -dot- org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCLibraryAlbumTableCellView.h"

#import "extensions/NSColor+VLCAdditions.h"
#import "extensions/NSFont+VLCAdditions.h"
#import "extensions/NSString+Helpers.h"
#import "extensions/NSView+VLCAdditions.h"

#import "views/VLCImageView.h"
#import "views/VLCTrackingView.h"

#import "main/VLCMain.h"

#import "library/VLCLibraryController.h"
#import "library/VLCLibraryDataTypes.h"
#import "library/VLCLibraryImageCache.h"
#import "library/VLCLibraryModel.h"
#import "library/VLCLibraryTableCellView.h"
#import "library/VLCLibraryTableView.h"
#import "library/VLCLibraryUIUnits.h"
#import "library/VLCLibraryWindow.h"

#import "library/audio-library/VLCLibraryAlbumTracksDataSource.h"
#import "library/audio-library/VLCLibraryAlbumTracksTableViewDelegate.h"

NSString * const VLCAudioLibraryCellIdentifier = @"VLCAudioLibraryCellIdentifier";
NSString * const VLCLibraryAlbumTableCellTableViewIdentifier = @"VLCLibraryAlbumTableCellTableViewIdentifier";
NSString * const VLCLibraryAlbumTableCellTableViewColumnIdentifier = @"VLCLibraryAlbumTableCellTableViewColumnIdentifier";

const CGFloat VLCLibraryAlbumTableCellViewDefaultHeight = 168.;

@interface VLCLibraryAlbumTableCellView ()
{
    VLCLibraryController *_libraryController;
    VLCLibraryAlbumTracksDataSource *_tracksDataSource;
    VLCLibraryAlbumTracksTableViewDelegate *_tracksTableViewDelegate;
    VLCLibraryTableView *_tracksTableView;
    NSTableColumn *_column;
}
@end

@implementation VLCLibraryAlbumTableCellView

+ (instancetype)fromNibWithOwner:(id)owner
{
    return (VLCLibraryAlbumTableCellView*)[NSView fromNibNamed:@"VLCLibraryAlbumTableCellView"
                                                     withClass:[VLCLibraryAlbumTableCellView class]
                                                     withOwner:owner];
}

+ (CGFloat)defaultHeight
{
    return VLCLibraryAlbumTableCellViewDefaultHeight;
}

- (CGFloat)height
{
    if (_representedAlbum == nil) {
        return -1;
    }

    const CGFloat artworkAndSecondaryLabelsHeight = VLCLibraryUIUnits.largeSpacing +
                                                    _representedImageView.frame.size.height +
                                                    VLCLibraryUIUnits.mediumSpacing +
                                                    _summaryTextField.frame.size.height +
                                                    VLCLibraryUIUnits.smallSpacing +
                                                    _yearTextField.frame.size.height +
                                                    VLCLibraryUIUnits.largeSpacing;

    if(_tracksTableView == nil) {
        return artworkAndSecondaryLabelsHeight;
    }

    const CGFloat titleAndTableViewHeight = VLCLibraryUIUnits.largeSpacing +
                                            _albumNameTextField.frame.size.height +
                                            VLCLibraryUIUnits.smallSpacing +
                                            _artistNameTextButton.frame.size.height +
                                            VLCLibraryUIUnits.smallSpacing +
                                            [self expectedTableViewHeight] +
                                            VLCLibraryUIUnits.largeSpacing;

    return titleAndTableViewHeight > artworkAndSecondaryLabelsHeight ? titleAndTableViewHeight : artworkAndSecondaryLabelsHeight;
}

- (CGFloat)expectedTableViewWidth
{
    // We are positioning the table view to the right of the album art, which means we need
    // to take into account the album's left spacing, right spacing, and the table view's
    // right spacing. In this case we are using large spacing for all of these. We also
    // throw in a little bit extra spacing to compensate for some mysterious internal spacing.
    return self.frame.size.width - _representedImageView.frame.size.width - VLCLibraryUIUnits.largeSpacing * 3.75;
}

- (CGFloat)expectedTableViewHeight
{
    const NSUInteger numberOfTracks = _representedAlbum.numberOfTracks;
    const CGFloat intercellSpacing = numberOfTracks > 1 ? (numberOfTracks - 1) * _tracksTableView.intercellSpacing.height : 0;
    return numberOfTracks * VLCLibraryTracksRowHeight + intercellSpacing + VLCLibraryUIUnits.mediumSpacing;
}

- (void)awakeFromNib
{
    [self setupTracksTableView];
    self.albumNameTextField.font = NSFont.VLCLibrarySubsectionHeaderFont;
    self.artistNameTextButton.font = NSFont.VLCLibrarySubsectionSubheaderFont;
    self.artistNameTextButton.action = @selector(detailAction:);
    self.trackingView.viewToHide = self.playInstantlyButton;

    if (@available(macOS 10.14, *)) {
        self.artistNameTextButton.contentTintColor = NSColor.VLCAccentColor;
    }

    [self prepareForReuse];

    NSNotificationCenter * const notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(handleAlbumUpdated:)
                               name:VLCLibraryModelAlbumUpdated
                             object:nil];
}

- (void)setupTracksTableView
{
    _tracksTableView = [[VLCLibraryTableView alloc] initWithFrame:NSZeroRect];
    _tracksTableView.identifier = VLCLibraryAlbumTableCellTableViewIdentifier;
    _column = [[NSTableColumn alloc] initWithIdentifier:VLCLibraryAlbumTableCellTableViewColumnIdentifier];
    _column.width = [self expectedTableViewWidth];
    _column.maxWidth = MAXFLOAT;
    [_tracksTableView addTableColumn:_column];

    if(@available(macOS 11.0, *)) {
        _tracksTableView.style = NSTableViewStyleFullWidth;
    }
    _tracksTableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _tracksTableView.rowHeight = VLCLibraryTracksRowHeight;
    _tracksTableView.backgroundColor = [NSColor clearColor];

    _tracksDataSource = [[VLCLibraryAlbumTracksDataSource alloc] init];
    _tracksTableViewDelegate = [[VLCLibraryAlbumTracksTableViewDelegate alloc] init];
    _tracksTableView.dataSource = _tracksDataSource;
    _tracksTableView.delegate = _tracksTableViewDelegate;
    _tracksTableView.doubleAction = @selector(tracksTableViewDoubleClickAction:);
    _tracksTableView.target = self;

    _tracksTableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_tracksTableView];
    NSString *horizontalVisualConstraints = [NSString stringWithFormat:@"H:|-%f-[_representedImageView]-%f-[_tracksTableView]-%f-|",
                                             VLCLibraryUIUnits.largeSpacing,
                                             VLCLibraryUIUnits.largeSpacing,
                                             VLCLibraryUIUnits.largeSpacing];
    NSString *verticalVisualContraints = [NSString stringWithFormat:@"V:|-%f-[_albumNameTextField]-%f-[_artistNameTextButton]-%f-[_tracksTableView]->=%f-|",
                                          VLCLibraryUIUnits.largeSpacing,
                                          VLCLibraryUIUnits.smallSpacing,
                                          VLCLibraryUIUnits.mediumSpacing,
                                          VLCLibraryUIUnits.largeSpacing];
    NSDictionary *dict = NSDictionaryOfVariableBindings(_tracksTableView, _representedImageView, _albumNameTextField, _artistNameTextButton);
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:horizontalVisualConstraints options:0 metrics:0 views:dict]];
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:verticalVisualContraints options:0 metrics:0 views:dict]];

    NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
    [notificationCenter addObserver:self
                           selector:@selector(handleTableViewSelectionIsChanging:)
                               name:NSTableViewSelectionIsChangingNotification
                             object:nil];
}

- (void)prepareForReuse
{
    [super prepareForReuse];

    self.representedImageView.image = nil;
    self.albumNameTextField.stringValue = @"";
    self.artistNameTextButton.title = @"";
    self.yearTextField.stringValue = @"";
    self.summaryTextField.stringValue = @"";
    self.yearTextField.hidden = NO;
    self.playInstantlyButton.hidden = YES;

    if (@available(macOS 10.14, *)) {
        self.artistNameTextButton.contentTintColor = NSColor.VLCAccentColor;
    }

    _tracksDataSource.representedAlbum = nil;
    [_tracksTableView reloadData];
}

- (void)handleAlbumUpdated:(NSNotification *)notification
{
    NSParameterAssert(notification);
    if (_representedAlbum == nil) {
        return;
    }

    VLCMediaLibraryAlbum * const album = (VLCMediaLibraryAlbum *)notification.object;
    if (album == nil || _representedAlbum.libraryID != album.libraryID) {
        return;
    }

    [self setRepresentedAlbum:album];
}

- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];

    // As it expects a scrollview as a parent, the table view will always resize itself and
    // we cannot directly set its size. However, it resizes itself according to its columns
    // and rows. We can therefore implicitly set its width by resizing the single column we
    // are using.
    //
    // Since a column is just an NSObject and not an actual NSView object, however, we cannot
    // use the normal autosizing/constraint systems and must instead calculate and set its
    // size manually.
    _column.width = [self expectedTableViewWidth];
}

- (IBAction)playInstantly:(id)sender
{
    if (!_libraryController) {
        _libraryController = VLCMain.sharedInstance.libraryController;
    }

    BOOL playImmediately = YES;
    for (VLCMediaLibraryMediaItem *mediaItem in [_representedAlbum tracksAsMediaItems]) {
        [_libraryController appendItemToPlaylist:mediaItem playImmediately:playImmediately];
        if (playImmediately) {
            playImmediately = NO;
        }
    }
}

- (void)detailAction:(id)sender
{
    if (!self.representedAlbum.actionableDetail) {
        return;
    }

    VLCLibraryWindow * const libraryWindow = VLCMain.sharedInstance.libraryWindow;
    id<VLCMediaLibraryItemProtocol> libraryItem = self.representedAlbum.actionableDetailLibraryItem;
    [libraryWindow presentLibraryItem:libraryItem];
}

- (void)setRepresentedAlbum:(VLCMediaLibraryAlbum *)representedAlbum
{
    _representedAlbum = representedAlbum;
    self.albumNameTextField.stringValue = _representedAlbum.title;
    self.artistNameTextButton.title = _representedAlbum.artistName;

    if (_representedAlbum.year > 0) {
        self.yearTextField.intValue = _representedAlbum.year;
    } else {
        self.yearTextField.hidden = YES;
    }

    if (_representedAlbum.summary.length > 0) {
        self.summaryTextField.stringValue = _representedAlbum.summary;
    } else {
        self.summaryTextField.stringValue = _representedAlbum.durationString;
    }

    const BOOL actionableDetail = self.representedAlbum.actionableDetail;
    self.artistNameTextButton.enabled = actionableDetail;
    if (@available(macOS 10.14, *)) {
        self.artistNameTextButton.contentTintColor = actionableDetail ? NSColor.VLCAccentColor : NSColor.secondaryLabelColor;
    }

    [VLCLibraryImageCache thumbnailForLibraryItem:_representedAlbum withCompletion:^(NSImage * const thumbnail) {
        self.representedImageView.image = thumbnail;
    }];

    __weak typeof(self) weakSelf = self; // Prevent retain cycle
    [_tracksDataSource setRepresentedAlbum:_representedAlbum withCompletion:^{
        __strong typeof(self) strongSelf = weakSelf;

        if (strongSelf) {
            [strongSelf->_tracksTableView reloadData];
        }
    }];
}

- (void)setRepresentedItem:(id<VLCMediaLibraryItemProtocol>)libraryItem
{
    VLCMediaLibraryAlbum * const album = (VLCMediaLibraryAlbum *)libraryItem;
    if (album != nil) {
        [self setRepresentedAlbum:album];
    }
}

- (void)tracksTableViewDoubleClickAction:(id)sender
{
    if (!_libraryController) {
        _libraryController = VLCMain.sharedInstance.libraryController;
    }

    NSArray *tracks = [_representedAlbum tracksAsMediaItems];
    NSUInteger trackCount = tracks.count;
    NSInteger clickedRow = _tracksTableView.clickedRow;
    if (clickedRow < trackCount) {
        [_libraryController appendItemToPlaylist:tracks[_tracksTableView.clickedRow] playImmediately:YES];
    }
}

- (void)handleTableViewSelectionIsChanging:(NSNotification *)notification
{
    NSParameterAssert(notification);
    NSTableView * const tableView = notification.object;
    NSAssert(tableView, @"Table view selection changing notification should carry valid table view");

    if (tableView != _tracksTableView &&
        tableView.identifier == VLCLibraryAlbumTableCellTableViewIdentifier) {

        [_tracksTableView deselectAll:self];
    }
}

@end
