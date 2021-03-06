//
//  MapBoxMainViewController.m
//  MapBoxiPad
//
//  Created by Justin R. Miller on 6/17/10.
//  Copyright Development Seed 2010. All rights reserved.
//

#import "MapBoxMainViewController.h"

#import "MapBoxAppDelegate.h"

#import "DSMapView.h"
#import "DSMapBoxTileSetManager.h"
#import "DSMapBoxDataOverlayManager.h"
#import "DSMapContents.h"
#import "DSMapBoxLayer.h"
#import "DSMapBoxDocumentSaveController.h"
#import "DSMapBoxMarkerManager.h"
#import "DSMapBoxHelpController.h"
#import "DSMapBoxFeedParser.h"
#import "DSMapBoxLayerAddTileStreamAlbumController.h"
#import "DSMapBoxLayerAddTileStreamBrowseController.h"
#import "DSMapBoxStyledModalNavigationController.h"
#import "DSMapBoxTileSourceInfiniteZoom.h"
#import "DSMapBoxGeoJSONParser.h"
#import "DSMapBoxAlertView.h"
#import "DSMapBoxLegendManager.h"
#import "DSMapBoxDownloadManager.h"
#import "DSMapBoxDownloadViewController.h"
#import "DSMapBoxNotificationCenter.h"
#import "DSMapBoxMailComposeViewController.h"
#import "DSMapBoxShareSheet.h"

#import "DSSound.h"

#import "SimpleKML.h"

#import "RMTileSource.h"
#import "RMOpenStreetMapSource.h"
#import "RMMapQuestOSMSource.h"
#import "RMMBTilesTileSource.h"
#import "RMTileStreamSource.h"

#import "TouchXML.h"

#import <CoreLocation/CoreLocation.h>
#import <QuartzCore/QuartzCore.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <MobileCoreServices/UTType.h>

#import "Reachability.h"

#import "UIImage_Additions.h"

#import "BALabel.h"

@interface MapBoxMainViewController ()

- (void)offlineAlert;
- (UIImage *)mapSnapshot;
- (void)layerImportAlertWithName:(NSString *)name;
- (void)setClusteringOn:(BOOL)clusteringOn;

@property (nonatomic, strong) UIPopoverController *layersPopover;
@property (nonatomic, strong) UIPopoverController *downloadsPopover;
@property (nonatomic, strong) DSMapBoxDataOverlayManager *dataOverlayManager;
@property (nonatomic, strong) DSMapBoxLayerManager *layerManager;
@property (nonatomic, strong) DSMapBoxDocumentSaveController *saveController;
@property (nonatomic, strong) DSMapBoxDocumentLoadController *loadController;
@property (nonatomic, strong) DSMapBoxLegendManager *legendManager;
@property (nonatomic, strong) UIActionSheet *documentsActionSheet;
@property (nonatomic, strong) DSMapBoxShareSheet *shareActionSheet;
@property (nonatomic, strong) Reachability *reachability;
@property (nonatomic, strong) NSURL *badParseURL;
@property (nonatomic, strong) NSDate *lastLayerAlertDate;
@property (nonatomic, assign) CLLocationCoordinate2D postRotationMapCenter;

@end

#pragma mark -

@implementation MapBoxMainViewController

@synthesize mapView;
@synthesize watermarkImage;
@synthesize attributionLabel;
@synthesize toolbar;
@synthesize layersButton;
@synthesize clusteringButton;
@synthesize downloadsButton;
@synthesize layersPopover;
@synthesize downloadsPopover;
@synthesize dataOverlayManager;
@synthesize layerManager;
@synthesize saveController;
@synthesize loadController;
@synthesize legendManager;
@synthesize documentsActionSheet;
@synthesize shareActionSheet;
@synthesize reachability;
@synthesize badParseURL;
@synthesize lastLayerAlertDate;
@synthesize postRotationMapCenter;

- (void)viewDidLoad
{
    [super viewDidLoad];

    // starting setup info
    //
    CLLocationCoordinate2D startingPoint;
    
    startingPoint.latitude  = kStartingLat;
    startingPoint.longitude = kStartingLon;
    
    // base view & map view
    //
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];
    
    RMMBTilesTileSource *source = [[RMMBTilesTileSource alloc] initWithTileSetURL:[[DSMapBoxTileSetManager defaultManager] defaultTileSetURL]];
    
	[[DSMapContents alloc] initWithView:self.mapView 
                             tilesource:source
                           centerLatLon:startingPoint
                              zoomLevel:kStartingZoom
                           maxZoomLevel:[source maxZoom]
                           minZoomLevel:[source minZoom]
                        backgroundImage:nil
                            screenScale:0.0];
    
    self.mapView.enableRotate = NO;
    self.mapView.deceleration = NO;
    
    self.mapView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"loading.png"]];

    self.mapView.contents.zoom = kStartingZoom;

    self.attributionLabel.verticalAlignment = BAVerticalAlignmentBottom;
    
    // hide cluster button to start
    //
    [self.toolbar setItems:[[NSMutableArray arrayWithArray:self.toolbar.items] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF = %@", self.clusteringButton]] animated:NO];

    // customize downloads button
    //
    UIButton *downloadsProgressButton = [UIButton buttonWithType:UIButtonTypeCustom];
    
    UIImage *downloadStateImage = [UIImage imageNamed:@"downloads0.png"];
    
    downloadsProgressButton.bounds = CGRectMake(0, 0, downloadStateImage.size.width, downloadStateImage.size.height);
    
    [downloadsProgressButton setImage:downloadStateImage forState:UIControlStateNormal];
    [downloadsProgressButton addTarget:self action:@selector(tappedDownloadsButton:) forControlEvents:UIControlEventTouchUpInside];

    self.downloadsButton.customView = downloadsProgressButton;
    
    // setup toolbar items as exclusive actions
    //
    for (id item in self.toolbar.items)
        if ([item isKindOfClass:[UIBarButtonItem class]])
            [self manageExclusiveItem:item];
    
    // data overlay, layer, and legend managers
    //
    self.dataOverlayManager = [[DSMapBoxDataOverlayManager alloc] initWithMapView:mapView];
    self.dataOverlayManager.mapView = self.mapView;
    self.mapView.delegate = self.dataOverlayManager;
    self.mapView.interactivityDelegate = self.dataOverlayManager;
    self.layerManager = [[DSMapBoxLayerManager alloc] initWithDataOverlayManager:dataOverlayManager overBaseMapView:mapView];
    self.layerManager.delegate = self;
    self.legendManager = [[DSMapBoxLegendManager alloc] initWithFrame:CGRectMake(5, 
                                                                                 self.view.frame.size.height - kDSMapBoxLegendManagerMaxHeight - 5, 
                                                                                 kDSMapBoxLegendManagerMaxWidth, 
                                                                                 kDSMapBoxLegendManagerMaxHeight)
                                                           parentView:self.view];
    
    // watch for net changes
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityDidChange:)
                                                 name:kReachabilityChangedNotification
                                               object:nil];
    
    self.reachability = [Reachability reachabilityForInternetConnection];
    [self.reachability startNotifier];
    
    // watch for zoom bounds limits
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(zoomBoundsReached:)
                                                 name:DSMapContentsZoomBoundsReached
                                               object:nil];
    
    self.lastLayerAlertDate = [NSDate date];
    
    // watch for new layer additions
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(layersAdded:)
                                                 name:DSMapBoxLayersAdded
                                               object:nil];
    
    // watch for web tile loads
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(webTileRequestStart:)
                                                 name:RMTileRequested
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(webTileRequestEnd:)
                                                 name:RMTileRetrieved
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(webTileRequestEnd:)
                                                 name:RMTileError
                                               object:nil];

    // watch for download events
    //
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadBegan:)
                                                 name:DSMapBoxDownloadBeganNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadQueueChanged:)
                                                 name:DSMapBoxDownloadQueueNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadProgressChanged:)
                                                 name:DSMapBoxDownloadProgressNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(downloadCompleted:)
                                                 name:DSMapBoxDownloadCompleteNotification
                                               object:nil];
    
    // restore app state
    //
    [self restoreState:self];
    
    // warn about any zipped mbtiles
    //
    BOOL showedZipAlert = NO;
    
    NSPredicate *zippedPredicate = [NSPredicate predicateWithFormat:@"self ENDSWITH '.mbtiles.zip'"];
    
    NSArray *zippedTiles = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[UIApplication sharedApplication] documentsFolderPath]
                                                                                error:NULL] filteredArrayUsingPredicate:zippedPredicate];
    
    NSMutableSet *seenZips = [NSMutableSet set];
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"seenZippedTiles"])
        [seenZips addObjectsFromArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"seenZippedTiles"]];
    
    for (NSString *zippedTile in zippedTiles)
    {
        if ( ! [seenZips containsObject:zippedTile] && ! showedZipAlert)
        {
            NSString *appName = [[NSProcessInfo processInfo] processName];
            
            [seenZips addObject:zippedTile];
            
            UIAlertView *zipAlert = [[UIAlertView alloc] initWithTitle:@"Zipped Tiles Found"

                                                               message:[NSString stringWithFormat:@"Your %@ documents contain zipped tiles. Please unzip these tiles first in order to use them in %@.", appName, appName] 
                                                              delegate:nil
                                                     cancelButtonTitle:nil
                                                     otherButtonTitles:@"OK", nil];
            
            [zipAlert show];
            
            showedZipAlert = YES;
        }
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:[seenZips allObjects] forKey:@"seenZippedTiles"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // make sure online tiles folder exists
    //
    NSString *onlineLayersFolder = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] preferencesFolderPath], kTileStreamFolderName];

    [[NSFileManager defaultManager] createDirectoryAtPath:onlineLayersFolder
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    
    // set clustering button state
    //
    if (((DSMapBoxMarkerManager *)mapView.topMostMapView.contents.markerManager).clusteringEnabled)
        [self setClusteringOn:YES];

    else
        [self setClusteringOn:NO];
    
#if ADHOC
    // add beta tester feedback button
    //
    UIImage *testFlightImage = [UIImage imageNamed:@"testflight.png"];
    
    UIButton *feedbackButton = [[UIButton alloc] initWithFrame:CGRectMake(self.view.bounds.size.width  - testFlightImage.size.width  - 10,
                                                                          self.view.bounds.size.height - testFlightImage.size.height - 10, 
                                                                          testFlightImage.size.width, 
                                                                          testFlightImage.size.height)];
    
    [feedbackButton setImage:testFlightImage forState:UIControlStateNormal];
    
    [feedbackButton addTarget:[TestFlight class] action:@selector(openFeedbackView) forControlEvents:UIControlEventTouchUpInside];
    
    feedbackButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    
    feedbackButton.alpha = 0.25;
    
    [self.view addSubview:feedbackButton];
#endif
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    self.postRotationMapCenter = self.mapView.contents.mapCenter;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    self.mapView.contents.mapCenter = self.postRotationMapCenter;
    
    if ([self.mapView.contents isKindOfClass:[DSMapContents class]])
        [(DSMapContents *)self.mapView.contents postZoom];
    
    [self.mapView.delegate mapViewRegionDidChange:self.mapView]; // trigger popover move
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification     object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapContentsZoomBoundsReached       object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxLayersAdded                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:RMTileRequested                      object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:RMTileRetrieved                      object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:RMTileError                          object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxDownloadBeganNotification    object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxDownloadQueueNotification    object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxDownloadProgressNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:DSMapBoxDownloadCompleteNotification object:nil];

    [reachability stopNotifier];
}

#pragma mark -

- (void)restoreState:(id)sender
{
    NSDictionary *baseMapState;
    NSArray *tileOverlayState;
    NSArray *dataOverlayState;
    
    // determine if document or global restore
    //
    if ([sender isKindOfClass:[NSString class]])
    {
        NSString *saveFile = [NSString stringWithFormat:@"%@/%@/%@.plist", [[UIApplication sharedApplication] preferencesFolderPath], kDSSaveFolderName, sender];
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:saveFile];
        
        baseMapState      = [dict objectForKey:@"baseMapState"];
        tileOverlayState  = [dict objectForKey:@"tileOverlayState"];
        dataOverlayState  = [dict objectForKey:@"dataOverlayState"];
    }
    else
    {
        baseMapState      = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"baseMapState"];
        tileOverlayState  = [[NSUserDefaults standardUserDefaults] arrayForKey:@"tileOverlayState"];
        dataOverlayState  = [[NSUserDefaults standardUserDefaults] arrayForKey:@"dataOverlayState"];
    }

    // load it up
    //
    if (baseMapState)
    {
        // get map center & zoom level
        //
        CLLocationCoordinate2D mapCenter = {
            .latitude  = [[baseMapState objectForKey:@"centerLatitude"]  floatValue],
            .longitude = [[baseMapState objectForKey:@"centerLongitude"] floatValue],
        };
        
        if (mapCenter.latitude <= kUpperLatitudeBounds && mapCenter.latitude >= kLowerLatitudeBounds)
            self.mapView.contents.mapCenter = mapCenter;
        
        if ([[baseMapState objectForKey:@"zoomLevel"] floatValue] >= kLowerZoomBounds && [[baseMapState objectForKey:@"zoomLevel"] floatValue] <= kUpperZoomBounds)
            self.mapView.contents.zoom = [[baseMapState objectForKey:@"zoomLevel"] floatValue];
    }
    
    // load tile overlay state(s)
    //
    NSMutableArray *newActiveTileLayers = [NSMutableArray array];
    
    if (tileOverlayState)
    {
        // remove current layers
        //
        NSArray *activeTileLayers = [self.layerManager.tileLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSelected = YES"]];
        for (DSMapBoxLayer *tileLayer in activeTileLayers)
            [self.layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[self.layerManager.tileLayers indexOfObject:tileLayer]
                                                                         inSection:DSMapBoxLayerSectionTile]];
        
        // toggle new ones
        //
        BOOL warnedOffline = NO;
        
        for (__strong NSString *tileOverlayURLString in tileOverlayState)
        {
            if ( ! [[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSOpenStreetMapURL] &&
                 ! [[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSMapQuestOSMURL])
                 tileOverlayURLString = [[[[UIApplication sharedApplication] applicationSandboxFolderPath] stringByAppendingString:@"/"] stringByAppendingString:tileOverlayURLString];
            
            NSURL *tileOverlayURL = [NSURL fileURLWithPath:tileOverlayURLString];
            
            for (DSMapBoxLayer *tileLayer in layerManager.tileLayers)
            {
                if ([tileLayer.URL isEqual:tileOverlayURL] &&
                    ([[NSFileManager defaultManager] fileExistsAtPath:[tileOverlayURL relativePath]] ||
                     [tileOverlayURL isEqual:kDSOpenStreetMapURL] || [tileOverlayURL isEqual:kDSMapQuestOSMURL]))
                {
                    [self.layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[self.layerManager.tileLayers indexOfObject:tileLayer] 
                                                                                 inSection:DSMapBoxLayerSectionTile]];
                    
                    [newActiveTileLayers addObject:tileLayer];
                }
            }
        
            // notify if any require net & we're offline if loading doc
            //
            if ([sender isKindOfClass:[NSString class]] &&
                ([[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSOpenStreetMapURL] || 
                 [[NSURL fileURLWithPath:tileOverlayURLString] isEqual:kDSMapQuestOSMURL]   || 
                 [[NSURL fileURLWithPath:tileOverlayURLString] isTileStreamURL]) &&
                ! warnedOffline && 
                [self.reachability currentReachabilityStatus] == NotReachable)
            {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Internet Connection"
                                                                message:@"At least one layer requires an internet connection, so it may not appear reliably."
                                                               delegate:nil
                                                      cancelButtonTitle:nil
                                                      otherButtonTitles:@"OK", nil];
                
                [alert performSelector:@selector(show) withObject:nil afterDelay:0.0];
                
                warnedOffline = YES;
            }
        }
    }
    
    // load data overlay state(s)
    //
    NSMutableArray *newActiveDataLayers = [NSMutableArray array];

    if (dataOverlayState)
    {
        // remove current layers
        //
        NSArray *activeDataLayers = [self.layerManager.dataLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSelected = YES"]];
        for (NSDictionary *dataLayer in activeDataLayers)
            [self.layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[self.layerManager.dataLayers indexOfObject:dataLayer]
                                                                         inSection:DSMapBoxLayerSectionData]];

        // toggle new ones
        //
        for (__strong NSString *dataOverlayURLString in dataOverlayState)
        {
            dataOverlayURLString = [[[[UIApplication sharedApplication] applicationSandboxFolderPath] stringByAppendingString:@"/"] stringByAppendingString:dataOverlayURLString];

            NSURL *dataOverlayURL = [NSURL fileURLWithPath:dataOverlayURLString];
            
            for (DSMapBoxLayer *dataLayer in self.layerManager.dataLayers)
            {
                if ([dataLayer.URL isEqual:dataOverlayURL] &&
                    [[NSFileManager defaultManager] fileExistsAtPath:[dataOverlayURL relativePath]])
                {
                    [self.layerManager toggleLayerAtIndexPath:[NSIndexPath indexPathForRow:[self.layerManager.dataLayers indexOfObject:dataLayer] 
                                                                                 inSection:DSMapBoxLayerSectionData]];
                    
                    [newActiveDataLayers addObject:dataLayer];
                }
            }
        }
    }

    // move selected layers to top of stack (currently sorted in tile manager load order)
    //
    [self.layerManager bringActiveTileLayersToTop:newActiveTileLayers dataLayers:newActiveDataLayers];
    
    // dismiss document loader
    //
    if ([sender isKindOfClass:[NSString class]])
        [self dismissModalViewControllerAnimated:YES];
}

- (void)saveState:(id)sender
{
    // get snapshot
    //
    NSData *mapSnapshot = UIImageJPEGRepresentation([self mapSnapshot], 1.0);
    
    // get base map state
    //
    NSDictionary *baseMapState = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithFloat:self.mapView.contents.mapCenter.latitude],  @"centerLatitude",
                                     [NSNumber numberWithFloat:self.mapView.contents.mapCenter.longitude], @"centerLongitude",
                                     [NSNumber numberWithFloat:self.mapView.contents.zoom],                @"zoomLevel",
                                     nil];
    
    // get tile overlay state(s)
    //
    NSArray *tileOverlayState = [[self.layerManager.tileLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSelected = YES"]] valueForKeyPath:@"URL.pathRelativeToApplicationSandbox"];
    
    // get data overlay state(s)
    //
    NSArray *dataOverlayState = [[self.layerManager.dataLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSelected = YES"]] valueForKeyPath:@"URL.pathRelativeToApplicationSandbox"];

    // determine if document or global save
    //
    if ([sender isKindOfClass:[UIBarButtonItem class]] || [sender isKindOfClass:[UIButton class]] || [sender isKindOfClass:[NSString class]])
    {
        NSString *saveFolderPath = [DSMapBoxDocumentLoadController saveFolderPath];
        
        BOOL isDirectory = NO;
        
        if ( ! [[NSFileManager defaultManager] fileExistsAtPath:saveFolderPath isDirectory:&isDirectory] || ! isDirectory)
            [[NSFileManager defaultManager] createDirectoryAtPath:saveFolderPath 
                                      withIntermediateDirectories:YES 
                                                       attributes:nil
                                                            error:NULL];
        
        NSString *stateName = nil;
        
        if ([sender isKindOfClass:[UIBarButtonItem class]] || [sender isKindOfClass:[UIButton class]]) // manual save
            stateName = self.saveController.name;
        
        else if ([sender isKindOfClass:[NSString class]]) // load controller save
            stateName = sender;
        
        if ([stateName length] && [[stateName componentsSeparatedByString:@"/"] count] < 2) // no slashes
        {
            if ( ! tileOverlayState)
                tileOverlayState = [NSArray array];
            
            if ( ! dataOverlayState)
                dataOverlayState = [NSArray array];
            
            NSDictionary *state = [NSDictionary dictionaryWithObjectsAndKeys:mapSnapshot,      @"mapSnapshot", 
                                                                             baseMapState,     @"baseMapState", 
                                                                             tileOverlayState, @"tileOverlayState", 
                                                                             dataOverlayState, @"dataOverlayState", 
                                                                             nil];
            
            NSString *savePath = [NSString stringWithFormat:@"%@/%@.plist", saveFolderPath, stateName];
            
            [state writeToFile:savePath atomically:YES];
            
            if (self.modalViewController.modalPresentationStyle == UIModalPresentationFormSheet) // save panel
                [self dismissModalViewControllerAnimated:YES];
        }
    }
    else
    {
        [[NSUserDefaults standardUserDefaults] setObject:mapSnapshot      forKey:@"mapSnapshot"];
        [[NSUserDefaults standardUserDefaults] setObject:baseMapState     forKey:@"baseMapState"];
        [[NSUserDefaults standardUserDefaults] setObject:tileOverlayState forKey:@"tileOverlayState"];
        [[NSUserDefaults standardUserDefaults] setObject:dataOverlayState forKey:@"dataOverlayState"];

        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (IBAction)tappedDocumentsButton:(id)sender
{
    if ( ! self.documentsActionSheet || ! self.documentsActionSheet.visible)
    {
        self.documentsActionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                                delegate:self
                                                       cancelButtonTitle:nil
                                                  destructiveButtonTitle:nil
                                                       otherButtonTitles:@"Load Map", @"Save Map", nil];
        
        [self.documentsActionSheet showFromBarButtonItem:sender animated:YES];
        
        [self manageExclusiveItem:self.documentsActionSheet];
    }

    else
        [self.documentsActionSheet dismissWithClickedButtonIndex:-1 animated:YES];
}

- (void)dismissModal
{
    [self dismissModalViewControllerAnimated:YES];
}

- (void)openKMLFile:(NSURL *)fileURL
{
    NSError *error = nil;
    
    SimpleKML *newKML = [SimpleKML KMLWithContentsOfURL:fileURL error:&error];

    if (error)
        [self dataLayerHandler:self didFailToHandleDataLayerAtURL:fileURL];

    else if (newKML)
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
        
        [TestFlight passCheckpoint:@"imported KML"];
    }
}

- (void)openRSSFile:(NSURL *)fileURL
{
    NSArray *feedItems = [DSMapBoxFeedParser itemsForFeed:[NSString stringWithContentsOfURL:fileURL
                                                                                   encoding:NSUTF8StringEncoding
                                                                                      error:NULL]];
    
    if ([feedItems count])
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
        
        [TestFlight passCheckpoint:@"imported GeoRSS"];
    }
    
    else
        [self dataLayerHandler:self didFailToHandleDataLayerAtURL:fileURL];
}

- (void)openGeoJSONFile:(NSURL *)fileURL
{
    NSArray *items = [DSMapBoxGeoJSONParser itemsForGeoJSON:[NSString stringWithContentsOfURL:fileURL
                                                                                     encoding:NSUTF8StringEncoding
                                                                                        error:NULL]];
    
    if ([items count])
    {
        NSString *source      = [fileURL relativePath];
        NSString *filename    = [[fileURL relativePath] lastPathComponent];
        NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
        
        [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
        
        [self layerImportAlertWithName:[fileURL lastPathComponent]];
        
        [TestFlight passCheckpoint:@"imported GeoJSON"];
    }
    
    else
        [self dataLayerHandler:self didFailToHandleDataLayerAtURL:fileURL];
}

- (void)openMBTilesFile:(NSURL *)fileURL
{
    NSString *source      = [fileURL relativePath];
    NSString *filename    = [[fileURL relativePath] lastPathComponent];
    NSString *destination = [NSString stringWithFormat:@"%@/%@", [[UIApplication sharedApplication] documentsFolderPath], filename];
    
    [[NSFileManager defaultManager] copyItemAtPath:source toPath:destination error:NULL];
    
    [self layerImportAlertWithName:[fileURL lastPathComponent]];
    
    [TestFlight passCheckpoint:@"imported MBTiles"];
}

- (IBAction)tappedLayersButton:(id)sender
{
    if ( ! self.layersPopover)
    {
        DSMapBoxLayerController *layerController = [[DSMapBoxLayerController alloc] initWithNibName:nil bundle:nil];
        
        layerController.layerManager = self.layerManager;
        layerController.delegate     = self;
        
        UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:layerController];
        
        self.layersPopover = [[UIPopoverController alloc] initWithContentViewController:wrapper];
        
        [self.layersPopover setPopoverContentSize:CGSizeMake(450, wrapper.view.bounds.size.height)];
        
        self.layersPopover.passthroughViews = nil;
    }

    [self manageExclusiveItem:self.layersPopover];

    if (self.layersPopover.popoverVisible)
        [self.layersPopover dismissPopoverAnimated:YES];
    
    else
        [self.layersPopover presentPopoverFromBarButtonItem:self.layersButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (IBAction)tappedClusteringButton:(id)sender
{
    [self manageExclusiveItem:sender];
    
    [TestFlight passCheckpoint:@"toggled clustering"];
    
    DSMapBoxMarkerManager *markerManager = (DSMapBoxMarkerManager *)mapView.topMostMapView.contents.markerManager;
    
    markerManager.clusteringEnabled = ! markerManager.clusteringEnabled;
    
    [self setClusteringOn:markerManager.clusteringEnabled];
    
    // reorder to ensure clusters or points are ordered properly
    //
    [self.layerManager reorderLayerDisplay];
}

- (IBAction)tappedHelpButton:(id)sender
{
    [TestFlight passCheckpoint:@"viewed help"];
    
    [self manageExclusiveItem:sender];
    
    DSMapBoxHelpController *helpController = [[DSMapBoxHelpController alloc] initWithNibName:nil bundle:nil];
    
    DSMapBoxStyledModalNavigationController *wrapper = [[DSMapBoxStyledModalNavigationController alloc] initWithRootViewController:helpController];
    
    helpController.navigationItem.title = [NSString stringWithFormat:@"%@ Help", [[NSProcessInfo processInfo] processName]];
    
    helpController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" 
                                                                                        style:UIBarButtonItemStyleBordered 
                                                                                       target:helpController
                                                                                       action:@selector(tappedHelpDoneButton:)
                                                                                    tintColor:kMapBoxBlue];
    
    wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
    wrapper.modalTransitionStyle   = UIModalTransitionStyleCoverVertical;
    
    [self presentModalViewController:wrapper animated:YES];
}

- (IBAction)tappedShareButton:(id)sender
{
    if ( ! self.shareActionSheet || ! self.shareActionSheet.visible)
    {
        self.shareActionSheet = [DSMapBoxShareSheet shareSheetWithImageCreationBlock:^(void) { return [self mapSnapshot]; } modalForViewController:self];
        
        [self.shareActionSheet showFromBarButtonItem:sender animated:YES];
        
        [self manageExclusiveItem:self.shareActionSheet];
    }
    
    else
        [self.shareActionSheet dismissWithClickedButtonIndex:-1 animated:YES];
}

- (IBAction)tappedDownloadsButton:(id)sender
{
    if ( ! self.downloadsPopover)
    {
        DSMapBoxDownloadViewController *downloadsController = [[DSMapBoxDownloadViewController alloc] initWithNibName:nil bundle:nil];
        
        UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:downloadsController];
        
        self.downloadsPopover = [[UIPopoverController alloc] initWithContentViewController:wrapper];
        
        self.downloadsPopover.passthroughViews = nil;
    }
    
    self.downloadsPopover.popoverContentSize = self.downloadsPopover.contentViewController.contentSizeForViewInPopover;

    [self manageExclusiveItem:self.downloadsPopover];
    
    if (self.downloadsPopover.popoverVisible)
        [self.downloadsPopover dismissPopoverAnimated:YES];
    
    else
    {
        [self.downloadsPopover presentPopoverFromBarButtonItem:self.downloadsButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
        
        [TestFlight passCheckpoint:@"opened downloads list"];
    }
}

- (void)setClusteringOn:(BOOL)clusteringOn
{
    UIButton *button;

    if ( ! self.clusteringButton.customView)
    {
        button = [UIButton buttonWithType:UIButtonTypeCustom];
        
        [button addTarget:self action:@selector(tappedClusteringButton:) forControlEvents:UIControlEventTouchUpInside];
        
        self.clusteringButton.customView = button;
    }
    
    else
        button = ((UIButton *)self.clusteringButton.customView);

    UIImage *stateImage = (clusteringOn ? [UIImage imageNamed:@"cluster_on.png"] : [UIImage imageNamed:@"cluster_off.png"]);

    button.bounds = CGRectMake(0, 0, stateImage.size.width, stateImage.size.height);

    [button setImage:stateImage forState:UIControlStateNormal];
}

#pragma mark -

- (void)downloadBegan:(NSNotification *)notification
{
    // post Growl-style notification
    //
    if ( ! self.downloadsPopover.isPopoverVisible)
    {
        NSURLConnection *download = [notification object];
        
        [[DSMapBoxNotificationCenter sharedInstance] notifyWithMessage:[NSString stringWithFormat:@"%@ download began", [download.originalRequest.URL lastPathComponent]]];
    }
}

- (void)downloadQueueChanged:(NSNotification *)notification
{
    // revert to empty progress image when no downloads in queue
    //
    if ( ! [((NSNumber *)[notification object]) boolValue])
    {
        UIButton *button = (UIButton *)self.downloadsButton.customView;

        UIImage *stateImage = [UIImage imageNamed:@"downloads0.png"];
        
        button.bounds = CGRectMake(0, 0, stateImage.size.width, stateImage.size.height);
        
        [button setImage:stateImage forState:UIControlStateNormal];
    }
}

- (void)downloadProgressChanged:(NSNotification *)notification
{
    // adjust downloads button image according to aggregate progress
    //
    if ([[notification object] isEqual:[DSMapBoxDownloadManager sharedManager]])
    {
        float progress = [[[notification userInfo] objectForKey:DSMapBoxDownloadProgressKey] floatValue];
        
        int index = round(8 * progress);
        
        UIImage *image = [UIImage imageNamed:[NSString stringWithFormat:@"downloads%i.png", index]];
        
        if ( ! [[((UIButton *)self.downloadsButton.customView) imageForState:UIControlStateNormal] isEqual:image])
            [((UIButton *)self.downloadsButton.customView) setImage:image forState:UIControlStateNormal];
    }
}

- (void)downloadCompleted:(NSNotification *)notification
{
    // get download in question
    //
    NSURLConnection *download = [notification object];
    
    // post Growl-style notification
    //
    if ( ! self.downloadsPopover.isPopoverVisible)
        [[DSMapBoxNotificationCenter sharedInstance] notifyWithMessage:[NSString stringWithFormat:@"%@ download complete", [download.originalRequest.URL lastPathComponent]]];
    
    // present local notification
    //
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground)
    {
        UILocalNotification *notification = [[UILocalNotification alloc] init];
        
        notification.alertAction = @"Launch";
        notification.alertBody   = [NSString stringWithFormat:@"The download of %@ has completed.", [download.originalRequest.URL lastPathComponent]];
        notification.soundName   = UILocalNotificationDefaultSoundName;
        
        [[UIApplication sharedApplication] presentLocalNotificationNow:notification];
    }
}

#pragma mark -

- (void)reachabilityDidChange:(NSNotification *)notification
{
    if ([(Reachability *)[notification object] currentReachabilityStatus] == NotReachable)
    {
        for (NSURL *layerURL in [[self.layerManager.tileLayers filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isSelected = YES"]] valueForKey:@"URL"])
        {
            if ([layerURL isEqual:kDSOpenStreetMapURL] || [layerURL isEqual:kDSMapQuestOSMURL] || [layerURL isTileStreamURL])
            {
                [self offlineAlert];
                
                return;
            }
        }
    }
}

- (void)offlineAlert
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Now Offline"
                                                    message:@"You are now offline. At least one active layer requires an internet connection, so it may not appear reliably."
                                                   delegate:nil
                                          cancelButtonTitle:nil
                                          otherButtonTitles:@"OK", nil];

    [alert performSelector:@selector(show) withObject:nil afterDelay:0.0];
}

- (UIImage *)mapSnapshot
{
    // zoom to even zoom level to avoid artifacts
    //
    CGFloat oldZoom = self.mapView.contents.zoom;
    CGPoint center  = CGPointMake(self.mapView.frame.size.width / 2, self.mapView.frame.size.height / 2);
    
    if ((CGFloat)ceil(oldZoom) - oldZoom < 0.5)    
        [self.mapView.contents zoomInToNextNativeZoomAt:center];
    
    else
        [self.mapView.contents zoomOutToNextNativeZoomAt:center];
    
    // get full screen snapshot without toolbar
    //
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(self.view.bounds.size.width, self.view.bounds.size.height), YES, 0);
    self.toolbar.hidden = YES;
    [self.view.layer renderInContext:UIGraphicsGetCurrentContext()];
    self.toolbar.hidden = NO;
    UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    // restore previous zoom
    //
    float factor = exp2f(oldZoom - [self.mapView.contents zoom]);
    [self.mapView.contents zoomByFactor:factor near:center];
    
    return snapshot;
}

- (void)zoomBoundsReached:(NSNotification *)notification
{
    if ( ! [[NSUserDefaults standardUserDefaults] boolForKey:@"skipWarningAboutZoom"])
    {
        if ([[NSDate date] timeIntervalSinceDate:self.lastLayerAlertDate] > 5.0)
        {
            NSString *message = [NSString stringWithFormat:@"All layers have built-in zoom limits. %@ lets you continue to zoom, but layers that don't support the current zoom level won't always appear reliably. %@ is now out of range.", [[NSProcessInfo processInfo] processName], [[notification object] valueForKeyPath:@"tileSource.shortName"]];
            
            DSMapBoxAlertView *alert = [[DSMapBoxAlertView alloc] initWithTitle:@"Layer Zoom Exceeded"
                                                                        message:message 
                                                                       delegate:self
                                                              cancelButtonTitle:@"Don't Warn"
                                                              otherButtonTitles:@"OK", nil];
            
            alert.context = @"zoom warning";
            
            [alert performSelector:@selector(show) withObject:nil afterDelay:0.5];
        }
    }
}

- (void)layerImportAlertWithName:(NSString *)name
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Layer Imported"
                                                    message:[NSString stringWithFormat:@"The new layer %@ was imported successfully. You may now find it in the layers menu.", name]
                                                   delegate:nil
                                          cancelButtonTitle:nil
                                          otherButtonTitles:@"OK", nil];
    
    [alert show];
}

- (void)layersAdded:(NSNotification *)notification
{
    // add layers to disk
    //
    NSArray *layerDictionaries = [[notification userInfo] objectForKey:@"selectedLayers"];
    
    NSMutableString *message = [NSMutableString string];
    
    for (NSDictionary *layerDictionary in layerDictionaries)
    {
        [message appendString:[layerDictionary objectForKey:@"name"]];
        [message appendString:@"\n"];
        
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [layerDictionary objectForKey:@"apiScheme"], @"apiScheme",
                                 [layerDictionary objectForKey:@"apiHostname"], @"apiHostname",
                                 [layerDictionary objectForKey:@"apiPort"], @"apiPort",
                                 [layerDictionary objectForKey:@"apiPath"], @"apiPath",
                                 [layerDictionary objectForKey:@"id"], @"id",
                                 ([layerDictionary objectForKey:@"bounds"] ? [[layerDictionary objectForKey:@"bounds"] componentsJoinedByString:@","] : @""), @"bounds",
                                 ([layerDictionary objectForKey:@"center"] ? [[layerDictionary objectForKey:@"center"] componentsJoinedByString:@","] : @""), @"center",
                                 ([layerDictionary objectForKey:@"name"] ? [layerDictionary objectForKey:@"name"] : @""), @"name",
                                 ([layerDictionary objectForKey:@"attribution"] ? [layerDictionary objectForKey:@"attribution"] : @""), @"attribution",
                                 ([layerDictionary objectForKey:@"type"] ? [layerDictionary objectForKey:@"type"] : @""), @"type",
                                 ([layerDictionary objectForKey:@"version"] ? [layerDictionary objectForKey:@"version"] : @""), @"version",
                                 [layerDictionary objectForKey:@"size"], @"size",
                                 [NSNumber numberWithInt:[[layerDictionary objectForKey:@"maxzoom"] intValue]], @"maxzoom",
                                 [NSNumber numberWithInt:[[layerDictionary objectForKey:@"minzoom"] intValue]], @"minzoom",
                                 ([layerDictionary objectForKey:@"description"] ? [layerDictionary objectForKey:@"description"] : @""), @"description",
                                 ([layerDictionary objectForKey:@"download"] ? [layerDictionary objectForKey:@"download"] : @""), @"download",
                                 ([layerDictionary objectForKey:@"filesize"] ? [layerDictionary objectForKey:@"filesize"] : @""), @"filesize",
                                 [NSDate dateWithTimeIntervalSince1970:([[layerDictionary objectForKey:@"mtime"] doubleValue] / 1000)], @"mtime",
                                 ([layerDictionary objectForKey:@"basename"] ? [layerDictionary objectForKey:@"basename"] : @""), @"basename",
                                 [layerDictionary objectForKey:@"tileURL"], @"tileURL",
                                 ([layerDictionary objectForKey:@"gridURL"] ? [layerDictionary objectForKey:@"gridURL"] : @""), @"gridURL",
                                 ([layerDictionary objectForKey:@"formatter"] ? [layerDictionary objectForKey:@"formatter"] : @""), @"formatter",
                                 ([layerDictionary objectForKey:@"template"] ? [layerDictionary objectForKey:@"template"] : @""), @"template",
                                 ([layerDictionary objectForKey:@"legend"] ? [layerDictionary objectForKey:@"legend"] : @""), @"legend",
                                 nil];
        
        NSString *prefsFolder = [[UIApplication sharedApplication] preferencesFolderPath];
        
        [dict writeToFile:[NSString stringWithFormat:@"%@/%@/%@.plist", prefsFolder, kTileStreamFolderName, [layerDictionary objectForKey:@"id"]] atomically:YES];
    }
    
    // animate layers into layer UI
    //
    NSArray *layerImages = [[notification userInfo] objectForKey:@"selectedImages"];
    
    NSArray *angles = [NSArray arrayWithObjects:[NSNumber numberWithInt:2], 
                                                [NSNumber numberWithInt:-3], 
                                                [NSNumber numberWithInt:0], 
                                                [NSNumber numberWithInt:-1], 
                                                [NSNumber numberWithInt:-2], 
                                                nil];

    NSMutableArray *imageViews = [NSMutableArray array];
    
    int max = [layerImages count];
    
    for (int i = 0; i < max; i++)
    {
        // create tile image view
        //
        UIImageView *imageView = [[UIImageView alloc] initWithImage:[[layerImages objectAtIndex:i] imageWithTransparentBorderOfWidth:1]];
        
        imageView.layer.shadowOpacity = 0.5;
        imageView.layer.shadowPath = [[UIBezierPath bezierPathWithRect:imageView.bounds] CGPath];
        imageView.layer.shadowOffset = CGSizeMake(0, 1);
        
        [self.view insertSubview:imageView aboveSubview:self.toolbar];
        
        // determine even spacing
        //
        int delta;
        
        if (max % 2 && i == max / 2)
            delta = 0;
        
        else if (max % 2)
            delta = ((max / 2) - i) * -50;
        
        else
            delta = (i >= (max / 2) ? (i - (max / 2) + 1) * 50 : ((max / 2) - i) * -50);
        
        // place & rotate initially
        //
        imageView.center = CGPointMake(self.mapView.center.x + delta, self.mapView.center.y);
        
        imageView.transform = CGAffineTransformMakeRotation([[angles objectAtIndex:(i % 5)] intValue] * M_PI / 180);
        
        // store reference for later
        //
        [imageViews addObject:imageView];
    }
    
    [UIView animateWithDuration:0.25
                          delay:0.0
                        options:UIViewAnimationCurveEaseInOut
                     animations:^(void)
                     {
                         // slide up from center of screen
                         //
                         for (UIView *view in imageViews)
                             view.center = CGPointMake(view.center.x, self.mapView.center.y - 200);
                     }
                     completion:^(BOOL finished)
                     {
                         [UIView animateWithDuration:0.25
                                               delay:0.75
                                             options:UIViewAnimationCurveEaseInOut
                                          animations:^(void)
                                          {
                                              if (max > 1)
                                              {
                                                  // play scrunching-together sound for multiple tiles
                                                  //
                                                  dispatch_delayed_ui_action(0.6, ^(void)
                                                  {
                                                      [DSSound playSoundNamed:@"paper_throw_start.wav"];
                                                  });
                                              }
                                              
                                              // move together into stack
                                              //
                                              for (UIView *view in imageViews)
                                                  view.center = CGPointMake(self.mapView.center.x, self.mapView.center.y - 200);
                                          }
                                          completion:^(BOOL finished)
                                          {
                                              // animate stack over to layers button
                                              //
                                              for (UIView *view in imageViews)
                                              {
                                                  // path
                                                  //
                                                  CGPoint startPoint = view.center;
                                                  CGPoint endPoint   = CGPointZero;
                                                  
                                                  for (UIBarButtonItem *item in self.toolbar.items)
                                                      if (item.action == @selector(tappedLayersButton:))
                                                          endPoint = [[[item valueForKeyPath:@"view"] valueForKeyPath:@"center"] CGPointValue];
                                                  
                                                  CGPoint controlPoint = CGPointMake(startPoint.x, startPoint.y + 100);
                                                  
                                                  UIBezierPath *arcPath = [UIBezierPath bezierPath];
                                                  
                                                  [arcPath moveToPoint:startPoint];
                                                  [arcPath addQuadCurveToPoint:endPoint controlPoint:controlPoint];
                                                  
                                                  CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
                                                  
                                                  pathAnimation.path = [arcPath CGPath];
                                                  pathAnimation.calculationMode = kCAAnimationPaced;
                                                  pathAnimation.timingFunctions = [NSArray arrayWithObject:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
                                                  
                                                  // opacity
                                                  //
                                                  CABasicAnimation *fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
                                                  
                                                  [fadeAnimation setToValue:[NSNumber numberWithFloat:0.75]];
                                                  
                                                  // size
                                                  //
                                                  CABasicAnimation *sizeAnimation = [CABasicAnimation animationWithKeyPath:@"bounds.size"];
                                                  
                                                  [sizeAnimation setToValue:[NSValue valueWithCGSize:CGSizeMake(4, 4)]];
                                                  
                                                  // shadow path
                                                  //
                                                  CABasicAnimation *shadowPathAnimation = [CABasicAnimation animationWithKeyPath:@"shadowPath"];
                                                  
                                                  [shadowPathAnimation setToValue:(id)[[UIBezierPath bezierPathWithRect:CGRectMake(0, 0, 4, 4)] CGPath]];
                                                  
                                                  // shadow fade
                                                  //
                                                  CABasicAnimation *shadowFadeAnimation = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
                                                  
                                                  [shadowFadeAnimation setToValue:[NSNumber numberWithFloat:0.0]];
                                                  
                                                  // group
                                                  //
                                                  CAAnimationGroup *group = [CAAnimationGroup animation];
                                                  
                                                  group.animations = [NSArray arrayWithObjects:pathAnimation, fadeAnimation, sizeAnimation, shadowPathAnimation, shadowFadeAnimation, nil];
                                                  
                                                  group.fillMode = kCAFillModeForwards;
                                                  group.duration = 1.0;
                                                  group.beginTime = CACurrentMediaTime() + 0.5;
                                                  group.removedOnCompletion = NO;
                                                  
                                                  [CATransaction begin];
                                                  [CATransaction setCompletionBlock:^(void)
                                                  {
                                                      [view removeFromSuperview];
                                                  }];
                                                  
                                                  [view.layer addAnimation:group forKey:nil];
                                                  
                                                  [CATransaction commit];
                                              }
                                              
                                              dispatch_delayed_ui_action(1.25, ^(void)
                                              {
                                                  // play landing sound
                                                  //
                                                  [DSSound playSoundNamed:@"paper_throw_end.wav"];
                                              });
                         }];
    }];
}

- (void)checkPasteboardForURL
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"skipPasteboardURLPrompt"] != YES)
    {
        // check clipboard for supported URL
        //
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSURL *pasteboardURL     = nil;

        for (NSString *type in [pasteboard pasteboardTypes])
        {
            if ( ! pasteboardURL)
            {
                if ([type isEqualToString:(NSString *)kUTTypeURL])
                    pasteboardURL = (NSURL *)[pasteboard valueForPasteboardType:(NSString *)kUTTypeURL];

                else if (UTTypeConformsTo((__bridge CFStringRef)type, kUTTypeText))
                    pasteboardURL = [NSURL URLWithString:(NSString *)[pasteboard valueForPasteboardType:type]];
            }
        }
                
        if (pasteboardURL)
        {
            if ([[NSArray arrayWithObjects:@"kml", @"kmz", @"xml", @"rss", @"geojson", @"json", @"mbtiles", nil] containsObject:[pasteboardURL pathExtension]])
            {
                NSString *message = [NSString stringWithFormat:@"You have recently copied the URL %@. Would you like to import the URL into %@?", pasteboardURL, [[NSProcessInfo processInfo] processName]];
                
                DSMapBoxAlertView *alert = [[DSMapBoxAlertView alloc] initWithTitle:@"Copied URL"
                                                                            message:message  
                                                                           delegate:self
                                                                  cancelButtonTitle:@"Don't Import"
                                                                  otherButtonTitles:@"Import", @"Don't Ask Again", nil];
                
                alert.context = pasteboardURL;
                
                [alert show];
                
                [TestFlight passCheckpoint:@"prompted to import clipboard URL"];
            }
        }
    }
}

- (void)webTileRequestStart:(NSNotification *)notification
{
    [DSMapBoxNetworkActivityIndicator addJob:[notification object]];
}

- (void)webTileRequestEnd:(NSNotification *)notification
{
    [DSMapBoxNetworkActivityIndicator removeJob:[notification object]];
}

#pragma mark -

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if ([actionSheet isEqual:self.documentsActionSheet])
    {
        if (buttonIndex == actionSheet.firstOtherButtonIndex)
        {
            self.loadController = [[DSMapBoxDocumentLoadController alloc] initWithNibName:nil bundle:nil];

            UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:loadController];
            
            wrapper.navigationBar.barStyle = UIBarStyleBlackTranslucent;
            
            self.loadController.navigationItem.leftBarButtonItem  = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                                     style:UIBarButtonItemStyleBordered
                                                                                                    target:self
                                                                                                    action:@selector(dismissModal)];
            
            self.loadController.delegate = self;
            
            wrapper.modalPresentationStyle = UIModalPresentationFullScreen;
            wrapper.modalTransitionStyle   = UIModalTransitionStyleFlipHorizontal;

            [self presentModalViewController:wrapper animated:YES];
        }
        else if (buttonIndex > -1)
        {
            self.saveController = [[DSMapBoxDocumentSaveController alloc] initWithNibName:nil bundle:nil];
            
            self.saveController.snapshot = [self mapSnapshot];
            
            NSUInteger i = 1;
            
            NSString *docName = nil;
            
            while ( ! docName)
            {
                if ([[NSFileManager defaultManager] fileExistsAtPath:[NSString stringWithFormat:@"%@/%@%@.plist", [DSMapBoxDocumentLoadController saveFolderPath], kDSSaveFileName, (i == 1 ? @"" : [NSString stringWithFormat:@" %i", i])]])
                    i++;
                
                else
                    docName = [NSString stringWithFormat:@"%@%@", kDSSaveFileName, (i == 1 ? @"" : [NSString stringWithFormat:@" %i", i])];
            }
            
            self.saveController.name = docName;
            
            DSMapBoxStyledModalNavigationController *wrapper = [[DSMapBoxStyledModalNavigationController alloc] initWithRootViewController:saveController];
            
            self.saveController.navigationItem.leftBarButtonItem  = [[UIBarButtonItem alloc] initWithTitle:@"Cancel"
                                                                                                     style:UIBarButtonItemStyleBordered
                                                                                                    target:self
                                                                                                    action:@selector(dismissModal)];
            
            self.saveController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" 
                                                                                                style:UIBarButtonItemStyleBordered 
                                                                                               target:self
                                                                                               action:@selector(saveState:)
                                                                                                 tintColor:kMapBoxBlue];
            
            wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
            wrapper.modalTransitionStyle   = UIModalTransitionStyleCoverVertical;

            [self presentModalViewController:wrapper animated:YES];
        }
    }
}

#pragma mark -

- (void)documentLoadController:(DSMapBoxDocumentLoadController *)controller didLoadDocumentWithName:(NSString *)name
{
    // put up dimmer & spinner (these will release when the load controller modal goes away)
    //
    UIView *dimmer = [[UIView alloc] initWithFrame:controller.view.frame];
    
    dimmer.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    
    [controller.view addSubview:dimmer];
    
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    
    [spinner startAnimating];
    
    spinner.center = dimmer.center;
    
    [dimmer addSubview:spinner];
    
    // actually load state
    //
    dispatch_delayed_ui_action(0.0, ^(void) { [self restoreState:name]; });
}

- (void)documentLoadController:(DSMapBoxDocumentLoadController *)controller wantsToSaveDocumentWithName:(NSString *)name
{
    [self saveState:name];
    
    [TestFlight passCheckpoint:@"saved document from main view"];
}

#pragma mark -

- (void)dataLayerHandler:(id)handler didUpdateTileLayers:(NSArray *)activeTileLayers
{
    // update attributions - first, remove empties
    //
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF != '' AND SELF != %@", [NSNull null]];
    
    NSArray *allAttributions = [[activeTileLayers valueForKey:@"attribution"] filteredArrayUsingPredicate:predicate];
    
    // de-dupe
    //
    NSSet *uniqueAttributions = [NSSet setWithArray:allAttributions];
    
    // update label
    //
    self.attributionLabel.text = [[uniqueAttributions allObjects] componentsJoinedByString:@" "];
    
    // update legends
    //
    self.legendManager.legendSources = [((DSMapContents *)mapView.contents).layerMapViews valueForKeyPath:@"contents.tileSource"];
}

- (void)dataLayerHandler:(id)handler didReorderTileLayers:(NSArray *)activeTileLayers
{
    // update legends
    //
    self.legendManager.legendSources = [((DSMapContents *)mapView.contents).layerMapViews valueForKeyPath:@"contents.tileSource"];
}

- (void)dataLayerHandler:(id)handler didUpdateDataLayers:(NSArray *)activeDataLayers
{
    if ([activeDataLayers count] > 0 && ! [self.toolbar.items containsObject:self.clusteringButton])
    {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:self.toolbar.items];

        [newItems insertObject:self.clusteringButton atIndex:([newItems count] - 1)];

        [self.toolbar setItems:newItems animated:YES];
    }
    else if ([activeDataLayers count] == 0 && [self.toolbar.items containsObject:self.clusteringButton])
    {
        NSMutableArray *newItems = [NSMutableArray arrayWithArray:self.toolbar.items];

        [newItems removeObject:self.clusteringButton];

        [self.toolbar setItems:newItems animated:YES];
    }
}

- (void)dataLayerHandler:(id)handler didFailToHandleDataLayerAtURL:(NSURL *)layerURL
{
    self.badParseURL = layerURL;
    
    NSString *message = [NSString stringWithFormat:@"%@ was unable to handle the layer file. Please contact us with a copy of the file in order to request support for it.", [[NSProcessInfo processInfo] processName]];
    
    DSMapBoxAlertView *alert = [[DSMapBoxAlertView alloc] initWithTitle:@"Layer Problem"
                                                                message:message
                                                               delegate:self
                                                      cancelButtonTitle:@"Don't Send"
                                                      otherButtonTitles:@"Send Mail", nil];
    
    alert.context = @"layer problem";
    
    [alert show];
    
    [TestFlight passCheckpoint:@"experienced layer problem"];
}

#pragma mark -

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    DSMapBoxAlertView *customAlertView = (DSMapBoxAlertView *)alertView;
    
    if ([customAlertView.context isKindOfClass:[NSString class]] && [customAlertView.context isEqualToString:@"layer problem"])
    {
        if (buttonIndex == alertView.firstOtherButtonIndex)
        {
            if ([MFMailComposeViewController canSendMail])
            {
                DSMapBoxMailComposeViewController *mailer = [[DSMapBoxMailComposeViewController alloc] init];
                
                mailer.mailComposeDelegate = self;
                
                [mailer setToRecipients:[NSArray arrayWithObject:KSupportEmail]];
                [mailer setMessageBody:@"<em>Please provide any additional details about this file or about the error you encountered here.</em>" isHTML:YES];
                
                if ([[self.badParseURL pathExtension] isEqualToString:@"kml"])
                {
                    [mailer setSubject:@"Problem KML file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"application/vnd.google-earth.kml+xml" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else if ([[self.badParseURL pathExtension] isEqualToString:@"kmz"])
                {
                    [mailer setSubject:@"Problem KMZ file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                      
                                     mimeType:@"application/vnd.google-earth.kmz" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else if ([[self.badParseURL pathExtension] isEqualToString:@"rss"] || [[self.badParseURL pathExtension] hasSuffix:@".xml"])
                {
                    [mailer setSubject:@"Problem RSS file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"application/rss+xml" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else if ([[self.badParseURL pathExtension] isEqualToString:@"geojson"] || [[self.badParseURL pathExtension] hasSuffix:@".json"])
                {
                    [mailer setSubject:@"Problem GeoJSON file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"text/plain" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                else
                {
                    [mailer setSubject:@"Problem file"];
                    
                    [mailer addAttachmentData:[NSData dataWithContentsOfURL:self.badParseURL]                       
                                     mimeType:@"application/octet-stream" 
                                     fileName:[[self.badParseURL absoluteString] lastPathComponent]];
                }
                
                [self presentModalViewController:mailer animated:YES];
                
                [TestFlight passCheckpoint:@"prompted to report layer problem"];
            }
            else
            {
                [UIAlertView showAlertViewWithTitle:@"Mail Not Setup"
                                            message:@"Please setup a Mail account in order to send a problem file."
                                  cancelButtonTitle:nil
                                  otherButtonTitles:[NSArray arrayWithObjects:@"OK", @"Show Me", nil]
                                            handler:^(UIAlertView *alertView, NSInteger buttonIndex)
                                            {
                                                if (buttonIndex == alertView.firstOtherButtonIndex + 1)
                                                    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"prefs:root=ACCOUNT_SETTINGS"]];
                                            }];
            }
        }
    }
    else if ([customAlertView.context isKindOfClass:[NSString class]] && [customAlertView.context isEqualToString:@"zoom warning"])
    {
        self.lastLayerAlertDate = [NSDate date];
        
        if (buttonIndex == alertView.cancelButtonIndex)
        {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"skipWarningAboutZoom"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
    else if ([customAlertView.context isKindOfClass:[NSURL class]])
    {
        if (buttonIndex == customAlertView.firstOtherButtonIndex)
        {
            // import clipboard URL
            //
            [TestFlight passCheckpoint:@"imported clipboard URL"];

            [[UIPasteboard generalPasteboard] setValue:nil forPasteboardType:(NSString *)kUTTypeURL];
            
            [(MapBoxAppDelegate *)[[UIApplication sharedApplication] delegate] openExternalURL:(NSURL *)customAlertView.context];
        }
        else if (buttonIndex == customAlertView.firstOtherButtonIndex + 1)
        {
            // don't prompt about clipboard URLs again
            //
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"skipPasteboardURLPrompt"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}

#pragma mark -

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
    switch (result)
    {
        case MFMailComposeResultFailed:
        {
            [self dismissModalViewControllerAnimated:NO];
            
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Mail Failed"
                                                            message:@"There was a problem sending the mail."
                                                           delegate:nil
                                                  cancelButtonTitle:nil
                                                  otherButtonTitles:@"OK", nil];
            
            [alert show];
            
            break;
        }
        default:
        {
            [self dismissModalViewControllerAnimated:YES];
        }
    }
}

#pragma mark -

- (void)zoomToLayer:(DSMapBoxLayer *)layer
{
    NSURL *layerURL = layer.URL;
    
    id source = nil;
    
    if ([layerURL isMBTilesURL])
        source = [[RMMBTilesTileSource alloc] initWithTileSetURL:layerURL];

    else if ([layerURL isTileStreamURL])
        source = [[RMTileStreamSource alloc] initWithReferenceURL:layerURL];
    
    if ( ! source)
        return;
    
    self.mapView.contents.zoom = ([source minZoomNative] >= kLowerZoomBounds ? [source minZoomNative] : kLowerZoomBounds);
    
    if ( ! [source coversFullWorld])
    {
        RMSphericalTrapezium bbox = [source latitudeLongitudeBoundingBox];
        
        CLLocationDegrees lon, lat;
        
        lon = (bbox.northeast.longitude + bbox.southwest.longitude) / 2;
        lat = (bbox.northeast.latitude  + bbox.southwest.latitude)  / 2;
        
        [self.mapView.contents moveToLatLong:CLLocationCoordinate2DMake(lat, lon)];
    }
}

- (void)presentAddLayerHelper
{
    if ([self.reachability currentReachabilityStatus] == NotReachable)
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"No Internet Connection"
                                                        message:@"Adding a layer requires an active internet connection."
                                                       delegate:nil
                                              cancelButtonTitle:nil
                                              otherButtonTitles:@"OK", nil];
        
        [alert show];
        
        return;
    }
    
    // dismiss layer UI
    //
    [self tappedLayersButton:self];

    DSMapBoxLayerAddTileStreamAlbumController *albumController = [[DSMapBoxLayerAddTileStreamAlbumController alloc] initWithNibName:nil bundle:nil];
    DSMapBoxStyledModalNavigationController *wrapper  = [[DSMapBoxStyledModalNavigationController alloc] initWithRootViewController:albumController];
    
    wrapper.modalPresentationStyle = UIModalPresentationFormSheet;
    wrapper.modalTransitionStyle   = UIModalTransitionStyleCoverVertical;

    [self presentModalViewController:wrapper animated:YES];
}

@end
