#import "MusicPreferences.h"
#import "MusicApp.h"
#import "Colorizer.h"
#include <sys/sysctl.h>

static NSArray *const NOTCHED_IPHONES = @[@"iPhone10,3", @"iPhone10,6", @"iPhone11,2", @"iPhone11,6", @"iPhone11,8", @"iPhone12,1", @"iPhone12,3", @"iPhone12,5"];
static BOOL isNotchediPhone;
static CGFloat screenWidth;
static NSInteger customRecentlyAddedColumnsNumber;
static UIColor *customNowPlayingViewTintColor;
static UIColor *systemBackgroundColor;

static MusicPreferences *preferences;
static Colorizer *colorizer;

void roundCorners(UIView* view, double topCornerRadius, double bottomCornerRadius)
{
	CGRect bounds = [view bounds];
	if(![preferences isIpad])
		bounds.size.height -= 54;
	
    CAShapeLayer *maskLayer = [CAShapeLayer layer];
    [maskLayer setFrame: bounds];
    [maskLayer setPath: ((UIBezierPath*)[UIBezierPath roundedRectBezierPath: bounds withTopCornerRadius: topCornerRadius withBottomCornerRadius: bottomCornerRadius]).CGPath];
    [[view layer] setMask: maskLayer];

    CAShapeLayer *frameLayer = [CAShapeLayer layer];
    [frameLayer setFrame: bounds];
    [frameLayer setLineWidth: [preferences musicAppBorderWidth]];
    [frameLayer setPath: [maskLayer path]];
    [frameLayer setFillColor: nil];

    [[view layer] addSublayer: frameLayer];
}

static void produceLightVibration()
{
	UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle: UIImpactFeedbackStyleLight];
	[gen prepare];
	[gen impactOccurred];
}

static NSString* getDeviceModel()
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *model = (char*)malloc(size);
    sysctlbyname("hw.machine", model, &size, NULL, 0);
    NSString *deviceModel = [NSString stringWithCString: model encoding: NSUTF8StringEncoding];
    free(model);
    return deviceModel;
}

// -------------------------------------- GET ARTWORK AND GENERATE COLORS  ------------------------------------------------

%group retrieveArtworkGroup

	%hook _MPCAVController

	- (void)_itemWillChange: (id)arg // FAST EFFICIENT WAY BUT DOES NOT WORK ON NON LOCAL MUSIC
	{
		%orig;

		id newItem = [arg objectForKeyedSubscript: @"new"];
		if(newItem && [newItem isKindOfClass: %c(MPCModelGenericAVItem)])
		{
			MPMediaItem *mediaItem = [newItem mediaItem];
			UIImage *image = [[mediaItem artwork] imageWithSize: CGSizeMake(128, 128)];

			[colorizer generateColorsForArtwork: image withTitle: [mediaItem title]];
		}
	}

	%end

	%hook NowPlayingContentView

	%property(nonatomic, retain) UIImageView *artworkImageView;

	- (void)layoutSubviews // USE THIS SECOND WAY TO READ THE ARTWORK IN CASE ARTWORK IS LOADED FROM INTERNET AND PREVIOUS WAY FAILS
	{
		%orig;

		if(![self artworkImageView] || [[self artworkImageView] observationInfo] == nil)
		{
			for(UIView *subview in [self subviews])
			{
				if([subview isKindOfClass: %c(_TtC16MusicApplication25ArtworkComponentImageView)])
				{
					[self setArtworkImageView: (UIImageView*)subview];
					break;
				}
			}
			if([self artworkImageView])
				[[self artworkImageView] addObserver: self forKeyPath: @"image" options: NSKeyValueObservingOptionNew context: nil];
		}
	}

	%new
	- (void)observeValueForKeyPath: (NSString*)keyPath ofObject: (id)object change: (NSDictionary<NSKeyValueChangeKey, id>*)change context: (void*)context
	{
		if([[self _viewControllerForAncestor] isKindOfClass: %c(MusicNowPlayingControlsViewController)] || [[self _viewControllerForAncestor] isKindOfClass: %c(_TtC16MusicApplication24MiniPlayerViewController)])
		{
			if([[[self artworkImageView] image] isKindOfClass: %c(UIImage)])
			{
				UIImage *image = [[self artworkImageView] image];
				if(image && [image size].width > 0)
				{
					NSString *title;
					if([[self _viewControllerForAncestor] isKindOfClass: %c(MusicNowPlayingControlsViewController)])
						title = [[(MusicNowPlayingControlsViewController*)[self _viewControllerForAncestor] titleLabel] text];
					else
						title = [[(_TtC16MusicApplication24MiniPlayerViewController*)[self _viewControllerForAncestor] nowPlayingItemTitleLabel] text];

					if([title hasSuffix: @" 🅴"])
						title = [title substringToIndex: ([title length] - 3)];
					
					dispatch_async(dispatch_get_main_queue(),
					^{
						[colorizer generateColorsForArtwork: image withTitle: title];
					});
				}	
			}
		}
	}

	%end

%end

// -------------------------------------- NowPlayingViewController  ------------------------------------------------

%group colorizeNowPlayingViewGroup

	%hook NowPlayingViewController

	- (id)init
	{
		self = %orig;
		[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(colorize) name: @"MusicArtworkChanged" object: nil];
		return self;
	}

	- (void)viewDidLayoutSubviews
	{
		%orig;
		[self colorize];
	}

	%new
	- (void)colorize
	{
		if([colorizer backgroundColor])
		{
			UIView *backgroundView = MSHookIvar<UIView*>(self, "backgroundView");
			UIView *contentView = [backgroundView contentView];
			UIView *newView = [contentView viewWithTag: 0xffeedd];
			if(!newView)
			{
				newView = [[UIView alloc] initWithFrame: [contentView bounds]];
				[newView setAutoresizingMask: UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
				[newView setTag: 0xffeedd];
				[newView setOpaque: NO];
				[newView setClipsToBounds: YES];

				if([preferences addMusicAppBorder])
				{
					if(isNotchediPhone)
						roundCorners(newView, 10, 40);
					else
					{
						[[newView layer] setCornerRadius: 10];
						[[newView layer] setBorderWidth: [preferences musicAppBorderWidth]];
						[[newView layer] setMaskedCorners: kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner];
					}
				}

				[contentView addSubview: newView];
			}
			
			[contentView setBackgroundColor: [UIColor clearColor]];

			[UIView animateWithDuration: [colorizer backgroundColorChangeDuration] animations:
			^{
				[newView setBackgroundColor: [colorizer backgroundColor]];
				if([preferences addMusicAppBorder])
				{
					if(isNotchediPhone)
						[((CAShapeLayer*)[[newView layer] sublayers][0]) setStrokeColor: [colorizer primaryColor].CGColor];
					else
						[[newView layer] setBorderColor: [colorizer primaryColor].CGColor];
				}
			}
			completion: nil];

			[MSHookIvar<MusicNowPlayingControlsViewController*>(self, "controlsViewController") colorize];
		}
	}

	%end

	// -------------------------------------- MusicNowPlayingControlsViewController  ------------------------------------------------

	%hook MusicNowPlayingControlsViewController

	%new
	- (void)colorize
	{
		UIView *bottomContainerView = MSHookIvar<UIView*>(self, "bottomContainerView");
		[bottomContainerView setCustomBackgroundColor: [UIColor clearColor]];
		[bottomContainerView setBackgroundColor: [UIColor clearColor]];

		UIView *grabberView = MSHookIvar<UIView*>(self, "grabberView");
		[grabberView setCustomBackgroundColor: [colorizer primaryColor]];
		[grabberView setBackgroundColor: [colorizer primaryColor]];

		[[self titleLabel] setCustomTextColor: [colorizer primaryColor]];
		[[self titleLabel] setTextColor: [colorizer primaryColor]];

		[[self subtitleButton] setCustomTitleColor: [colorizer secondaryColor]];
		[[self subtitleButton] setTitleColor: [colorizer secondaryColor] forState: UIControlStateNormal];
		
		[[self accessibilityLyricsButton] setSpecialButton: @1];
		[[self accessibilityLyricsButton] updateButtonColor];

		[[self routeButton] setCustomTintColor: [colorizer secondaryColor]];
		[[self routeButton] setTintColor: [colorizer secondaryColor]];

		[[self routeLabel] setCustomTextColor: [colorizer secondaryColor]];
		[[self routeLabel] setTextColor: [colorizer secondaryColor]];

		[[self accessibilityQueueButton] setSpecialButton: @2];
		[[self accessibilityQueueButton] updateButtonColor];

		UIView *queueModeBadgeView = MSHookIvar<UIView*>(self, "queueModeBadgeView");
		[queueModeBadgeView setCustomTintColor: [colorizer backgroundColor]];
		[queueModeBadgeView setTintColor: [colorizer backgroundColor]];
		[queueModeBadgeView setCustomBackgroundColor: [colorizer primaryColor]];
		[queueModeBadgeView setBackgroundColor: [colorizer primaryColor]];

		[[self leftButton] colorize];
		[[self playPauseStopButton] colorize];
		[[self rightButton] colorize];

		[[[self contextButton] superview] setAlpha: 1.0];
		[[self contextButton] colorize];

		[MSHookIvar<PlayerTimeControl*>(self, "timeControl") colorize];
		[MSHookIvar<MPVolumeSlider*>(self, "volumeSlider") colorize];
	}

	%end

	// -------------------------------------- ContextualActionsButton  ------------------------------------------------

	%hook ContextualActionsButton

	%new
	- (void)colorize
	{
		[self setCustomTintColor: [colorizer primaryColor]];
		[self setTintColor: [colorizer primaryColor]];

		UIImageView *ellipsisImageView = MSHookIvar<UIImageView*>(self, "ellipsisImageView");
		[ellipsisImageView setCustomTintColor: [colorizer backgroundColor]];
		[ellipsisImageView setTintColor: [colorizer backgroundColor]];
	}

	%end

	// -------------------------------------- PlayerTimeControl  ------------------------------------------------

	%hook PlayerTimeControl

	%new
	- (void)colorize
	{
		[self setCustomTintColor: [colorizer primaryColor]];
		[self setTintColor: [colorizer primaryColor]];

		MSHookIvar<UIColor*>(self, "trackingTintColor") = [colorizer primaryColor];

		[MSHookIvar<UILabel*>(self, "remainingTimeLabel") setCustomTextColor: [colorizer primaryColor]];
		[MSHookIvar<UILabel*>(self, "remainingTimeLabel") setTextColor: [colorizer primaryColor]];
		[MSHookIvar<UIView*>(self, "remainingTrack") setCustomBackgroundColor: [colorizer secondaryColor]];
		[MSHookIvar<UIView*>(self, "remainingTrack") setBackgroundColor: [colorizer secondaryColor]];
		[MSHookIvar<UIView*>(self, "knobView") setCustomBackgroundColor: [colorizer primaryColor]];
		[MSHookIvar<UIView*>(self, "knobView") setBackgroundColor: [colorizer primaryColor]];
	}

	%end

	// -------------------------------------- MPVolumeSlider  ------------------------------------------------

	%hook MPVolumeSlider

	%new
	- (void)colorize
	{
		if([self tintColor] != [colorizer primaryColor])
		{
			[self setCustomTintColor: [colorizer primaryColor]];
			[self setTintColor: [colorizer primaryColor]];

			[[self _minValueView] setTintColor: [colorizer primaryColor]];
			[[self _maxValueView] setTintColor: [colorizer primaryColor]];

			[self setCustomMinimumTrackTintColor: [colorizer primaryColor]];
			[self setMinimumTrackTintColor: [colorizer primaryColor]];
			[self setCustomMaximumTrackTintColor: [colorizer secondaryColor]];
			[self setMaximumTrackTintColor: [colorizer secondaryColor]];

			[[self thumbView] setCustomTintColor: [colorizer primaryColor]];
			[[self thumbView] setTintColor: [colorizer primaryColor]];
			[[[self thumbView] layer] setShadowColor: [colorizer primaryColor].CGColor];
			if([[self thumbImageForState: UIControlStateNormal] renderingMode] != UIImageRenderingModeAlwaysTemplate)
				[self setThumbImage: [[self thumbImageForState: UIControlStateNormal] imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate] forState: UIControlStateNormal];
		}
	}

	%end

%end

// -------------------------------------- QUEUE STUFF  ------------------------------------------------

%group colorizeQueueViewGroup

	%hook NowPlayingQueueViewController

	- (id)init
	{
		self = %orig;
		[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(colorize) name: @"MusicArtworkChanged" object: nil];
		return self;
	}

	- (void)viewDidLayoutSubviews
	{
		%orig;
		[self colorize];
	}

	%new
	- (void)colorize
	{
		[MSHookIvar<NowPlayingQueueHeaderView*>(self, "upNextHeader") colorize];
		[MSHookIvar<NowPlayingHistoryHeaderView*>(self, "historyHeader") colorize];
	}

	%end

	%hook NowPlayingHistoryHeaderView

	- (void)setBackgroundColor: (UIColor*)color
	{
		if([colorizer backgroundColor])
			%orig([colorizer backgroundColor]);
		else 
			%orig;
	}

	%new
	- (void)colorize
	{
		if([colorizer backgroundColor])
		{
			[UIView animateWithDuration: [colorizer backgroundColorChangeDuration] animations:
			^{
				[(UIView*)self setBackgroundColor: [colorizer backgroundColor]];
			}
			completion: nil];
			
			for (UIView *subview in [self subviews])
			{
				if([subview isKindOfClass: %c(UILabel)]) [(UILabel*)subview setTextColor: [colorizer primaryColor]];
				if([subview isKindOfClass: %c(UIButton)]) [(UIButton*)subview setTintColor: [colorizer secondaryColor]];
			}
		}
	}

	%end

	%hook NowPlayingQueueHeaderView

	- (void)setBackgroundColor: (UIColor*)color
	{
		if([colorizer backgroundColor]) 
			%orig([colorizer backgroundColor]);
		else 
			%orig;
	}

	- (void)viewDidLayoutSubviews
	{
		%orig;
		[self colorize];
	}

	%new
	- (void)colorize
	{
		if([colorizer backgroundColor])
		{
			if([(UIView*)self backgroundColor] != [colorizer backgroundColor])
			{
				[UIView animateWithDuration: [colorizer backgroundColorChangeDuration] animations:
				^{
					[(UIView*)self setBackgroundColor: [colorizer backgroundColor]];
				}
				completion: nil];
			}

			[MSHookIvar<UILabel*>(self, "titleLabel") setTextColor: [colorizer primaryColor]];
			[MSHookIvar<MPButton*>(self, "subtitleButton") setTintColor: [colorizer secondaryColor]];

			MPButton *shuffleButton = MSHookIvar<MPButton*>(self, "shuffleButton");
			[shuffleButton setSpecialButton: @3];
			[shuffleButton updateButtonColor];

			MPButton *repeatButton = MSHookIvar<MPButton*>(self, "repeatButton");
			[repeatButton setSpecialButton: @3];
			[repeatButton updateButtonColor];
		}
	}

	%end

	%hook QueueGradientView

	- (void)layoutSubviews
	{
		%orig;
		[self setHidden: YES];
	}

	%end

%end

// -------------------------------------- MiniPlayerViewController  ------------------------------------------------

%group colorizeMiniPlayerGroup

	%hook MiniPlayerViewController

	- (void)viewDidLayoutSubviews
	{
		%orig;
		[self colorize];
	}

	- (void)controller: (id)arg1 defersResponseReplacement: (id)arg2
	{
		%orig;
		dispatch_async(dispatch_get_main_queue(),
		^{
			[self colorize];
		});
	}

	%new
	- (void)colorize
	{
		if([colorizer backgroundColor])
		{
			[[self view] setCustomBackgroundColor: [colorizer backgroundColor]];
			[[self view] setBackgroundColor: [colorizer backgroundColor]];

			[[[self nowPlayingItemTitleLabel] layer] setCompositingFilter: 0];
			[[self nowPlayingItemTitleLabel] _setTextColorFollowsTintColor: NO];
			[[self nowPlayingItemTitleLabel] setTextColor: [colorizer primaryColor]];

			[[self nowPlayingItemRouteLabel] _setTextColorFollowsTintColor: NO];
			[[self nowPlayingItemRouteLabel] setTextColor: [colorizer secondaryColor]];
			
			[[self playPauseButton] colorize];
			[[self skipButton] colorize];
		}
	}

	%end

%end

%group sharedViewsGroup

	// -------------------------------------- NowPlayingTransportButton  ------------------------------------------------

	%hook NowPlayingTransportButton

	- (void)setImage: (id)arg1 forState: (unsigned long long)arg2
	{
		%orig([(UIImage*)arg1 imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate], arg2);
	}

	%new
	- (void)colorize
	{
		[[self imageView] setCustomTintColor: [colorizer primaryColor]];
		[[self imageView] setTintColor: [colorizer primaryColor]];
		[[[self imageView] layer] setCompositingFilter: 0];

		[MSHookIvar<UIView*>(self, "highlightIndicatorView") setBackgroundColor: [colorizer primaryColor]];
	}

	%end

%end

// -------------------------------------- SET 3 COLUMNS ALBUMS - IPHONE ONLY  ------------------------------------------------

%group customRecentlyAddedColumnsNumberGroup

	static CGSize albumSize;
	static BOOL isAlbumSizeSet = NO;

	%hook UICollectionViewFlowLayout

	- (void)setItemSize: (CGSize)arg
	{
		if(!isAlbumSizeSet)
		{
			if(customRecentlyAddedColumnsNumber == 3)
				albumSize = CGSizeMake(screenWidth / 3.8, arg.height * 0.63);
			else if(customRecentlyAddedColumnsNumber == 4)
				albumSize = CGSizeMake(screenWidth / 5.2, arg.height * 0.55);
			else if(customRecentlyAddedColumnsNumber == 5)
				albumSize = CGSizeMake(screenWidth / 6.5, arg.height * 0.48);
			
			isAlbumSizeSet = YES;
		}
		
		%orig(albumSize);
	}

	%end

%end

// -------------------------------------- VIBRATIONS  ------------------------------------------------

%group vibrateMusicAppGroup

	%hook  UITableViewCell

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook UICollectionViewCell

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook UITabBarButton

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook UIButton

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook MPRouteButton

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook UISegmentedControl

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook UITextField

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook _UIButtonBarButton

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook TimeSlider

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

	%hook MPVolumeSlider

	- (void)touchesBegan: (id)arg1 withEvent: (id)arg2
	{
		produceLightVibration();
		%orig;
	}

	%end

%end

// -------------------------------------- NO QUEUE HUD  ------------------------------------------------

// Original tweak by @nahtedetihw: https://github.com/nahtedetihw/MusicQueueBeGone

%group hideQueueHUDGroup

	%hook ContextActionsHUDViewController

	- (void)viewDidLoad
	{

	}
		
	%end

%end

// -------------------------------------- MUSIC APP GENERAL TINT COLOR  ------------------------------------------------

%group customMusicAppTintColorGroup

	%hook UIColor

	+ (id)systemPinkColor
	{
		return [preferences customMusicAppTintColor];
	}

	%end

%end

// -------------------------------------- NOW PLAYING VIEW CUSTOM TINT COLOR  ------------------------------------------------

%group customMusicAppNowPlayingViewTintColorGroup

	// -------------------------------------- MusicNowPlayingControlsViewController  ------------------------------------------------

	%hook MusicNowPlayingControlsViewController

	- (void)viewDidLayoutSubviews	
	{
		%orig;
		[self colorize];
	}

	%new
	- (void)colorize
	{
		if([[self traitCollection] userInterfaceStyle] == UIUserInterfaceStyleDark)
			systemBackgroundColor = [UIColor blackColor];
		else
			systemBackgroundColor = [UIColor whiteColor];

		UIView *grabberView = MSHookIvar<UIView*>(self, "grabberView");
		[grabberView setCustomBackgroundColor: customNowPlayingViewTintColor];
		[grabberView setBackgroundColor: customNowPlayingViewTintColor];

		[[self subtitleButton] setCustomTitleColor: customNowPlayingViewTintColor];
		[[self subtitleButton] setTitleColor: customNowPlayingViewTintColor forState: UIControlStateNormal];
		
		[[self accessibilityLyricsButton] setSpecialButton: @1];
		[[self accessibilityLyricsButton] setCustomButtonTintColorWithBackgroundColor: systemBackgroundColor];

		[[self routeButton] setCustomTintColor: customNowPlayingViewTintColor];
		[[self routeButton] setTintColor: customNowPlayingViewTintColor];

		[[self routeLabel] setCustomTextColor: customNowPlayingViewTintColor];
		[[self routeLabel] setTextColor: customNowPlayingViewTintColor];

		[[self accessibilityQueueButton] setSpecialButton: @2];
		[[self accessibilityQueueButton] setCustomButtonTintColorWithBackgroundColor: systemBackgroundColor];

		UIView *queueModeBadgeView = MSHookIvar<UIView*>(self, "queueModeBadgeView");
		[queueModeBadgeView setCustomTintColor: systemBackgroundColor];
		[queueModeBadgeView setTintColor: systemBackgroundColor];
		[queueModeBadgeView setCustomBackgroundColor: customNowPlayingViewTintColor];
		[queueModeBadgeView setBackgroundColor: customNowPlayingViewTintColor];

		[[self leftButton] colorize];
		[[self playPauseStopButton] colorize];
		[[self rightButton] colorize];

		[[[self contextButton] superview] setAlpha: 1.0];
		[[self contextButton] colorize];

		[MSHookIvar<PlayerTimeControl*>(self, "timeControl") colorize];
		[MSHookIvar<MPVolumeSlider*>(self, "volumeSlider") colorize];
	}

	%end

	// -------------------------------------- ContextualActionsButton  ------------------------------------------------

	%hook ContextualActionsButton

	%new
	- (void)colorize
	{
		[self setCustomTintColor: customNowPlayingViewTintColor];
		[self setTintColor: customNowPlayingViewTintColor];

		UIImageView *ellipsisImageView = MSHookIvar<UIImageView*>(self, "ellipsisImageView");
		[ellipsisImageView setCustomTintColor: systemBackgroundColor];
		[ellipsisImageView setTintColor: systemBackgroundColor];
	}

	%end

	// -------------------------------------- PlayerTimeControl  ------------------------------------------------

	%hook PlayerTimeControl

	%new
	- (void)colorize
	{
		[self setCustomTintColor: customNowPlayingViewTintColor];
		[self setTintColor: customNowPlayingViewTintColor];

		MSHookIvar<UIColor*>(self, "trackingTintColor") = customNowPlayingViewTintColor;

		[MSHookIvar<UILabel*>(self, "remainingTimeLabel") setCustomTextColor: customNowPlayingViewTintColor];
		[MSHookIvar<UILabel*>(self, "remainingTimeLabel") setTextColor: customNowPlayingViewTintColor];
		[MSHookIvar<UIView*>(self, "remainingTrack") setCustomBackgroundColor: customNowPlayingViewTintColor];
		[MSHookIvar<UIView*>(self, "remainingTrack") setBackgroundColor: customNowPlayingViewTintColor];
		[MSHookIvar<UIView*>(self, "knobView") setCustomBackgroundColor: customNowPlayingViewTintColor];
		[MSHookIvar<UIView*>(self, "knobView") setBackgroundColor: customNowPlayingViewTintColor];
	}

	%end

	// -------------------------------------- NowPlayingTransportButton  ------------------------------------------------

	%hook NowPlayingTransportButton

	- (void)setImage: (id)arg1 forState: (unsigned long long)arg2
	{
		%orig([(UIImage*)arg1 imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate], arg2);
	}

	%new
	- (void)colorize
	{
		[[self imageView] setCustomTintColor: customNowPlayingViewTintColor];
		[[self imageView] setTintColor: customNowPlayingViewTintColor];
		[[[self imageView] layer] setCompositingFilter: 0];

		[MSHookIvar<UIView*>(self, "highlightIndicatorView") setBackgroundColor: customNowPlayingViewTintColor];
	}

	%end

	// -------------------------------------- MPVolumeSlider  ------------------------------------------------

	%hook MPVolumeSlider

	%new
	- (void)colorize
	{
		[self setCustomTintColor: customNowPlayingViewTintColor];
		[self setTintColor: customNowPlayingViewTintColor];

		[[self _minValueView] setTintColor: customNowPlayingViewTintColor];
		[[self _maxValueView] setTintColor: customNowPlayingViewTintColor];

		[self setCustomMinimumTrackTintColor: customNowPlayingViewTintColor];
		[self setMinimumTrackTintColor: customNowPlayingViewTintColor];
		[self setCustomMaximumTrackTintColor: customNowPlayingViewTintColor];
		[self setMaximumTrackTintColor: customNowPlayingViewTintColor];

		[[self thumbView] setCustomTintColor: customNowPlayingViewTintColor];
		[[self thumbView] setTintColor: customNowPlayingViewTintColor];
		[[[self thumbView] layer] setShadowColor: customNowPlayingViewTintColor.CGColor];
		if([[self thumbImageForState: UIControlStateNormal] renderingMode] != UIImageRenderingModeAlwaysTemplate)
			[self setThumbImage: [[self thumbImageForState: UIControlStateNormal] imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate] forState: UIControlStateNormal];
	}

	%end

	%hook MiniPlayerViewController

	- (void)viewDidLayoutSubviews
	{
		%orig;
		[self colorize];
	}

	- (void)controller: (id)arg1 defersResponseReplacement: (id)arg2
	{
		%orig;
		dispatch_async(dispatch_get_main_queue(),
		^{
			[self colorize];
		});
	}

	%new
	- (void)colorize
	{
		[[self playPauseButton] colorize];
		[[self skipButton] colorize];
	}

	%end

	%hook NowPlayingQueueViewController

	- (void)viewDidLayoutSubviews
	{
		%orig;
		[self colorize];
	}

	%new
	- (void)colorize
	{
		[MSHookIvar<NowPlayingQueueHeaderView*>(self, "upNextHeader") colorize];
		[MSHookIvar<NowPlayingHistoryHeaderView*>(self, "historyHeader") colorize];
	}

	%end

	%hook NowPlayingHistoryHeaderView

	%new
	- (void)colorize
	{
		for (UIView *subview in [self subviews])
		{
			if([subview isKindOfClass: %c(UIButton)])
				[(UIButton*)subview setTintColor: customNowPlayingViewTintColor];
		}
	}

	%end

	%hook NowPlayingQueueHeaderView

	- (void)viewDidLayoutSubviews
	{
		%orig;
		[self colorize];
	}

	%new
	- (void)colorize
	{
		[MSHookIvar<MPButton*>(self, "subtitleButton") setTintColor: customNowPlayingViewTintColor];

		MPButton *shuffleButton = MSHookIvar<MPButton*>(self, "shuffleButton");
		[shuffleButton setSpecialButton: @3];
		[shuffleButton setCustomButtonTintColorWithBackgroundColor: systemBackgroundColor];

		MPButton *repeatButton = MSHookIvar<MPButton*>(self, "repeatButton");
		[repeatButton setSpecialButton: @3];
		[repeatButton setCustomButtonTintColorWithBackgroundColor: systemBackgroundColor];
	}

	%end

%end

// -------------------------------------- ALWAYS KEEP OR CLEAR QUEUE --------------------------------------

%group hideKeepOrClearAlertGroup

	// Original tweak by @arandomdev: https://github.com/arandomdev/AlwaysClear

	%hook MusicApplicationTabController

	- (void)presentViewController: (UIViewController*)viewControllerToPresent animated: (BOOL)flag completion: (void (^)(void))completion
	{
		if([viewControllerToPresent isKindOfClass: [UIAlertController class]])
		{
			UIAlertController *alertController = (UIAlertController*)viewControllerToPresent;
			if([[alertController message] containsString: @"playing"] && [[alertController message] containsString: @"queue"])
			{
				UIAlertAction *clearAction = alertController.actions[[preferences keepOrClearAlertAction]];
				clearAction.handler(clearAction);
				
				if(completion)
					completion();
			}
		}
		else 
			%orig;
	}

	%end

%end

// -------------------------------------- HIDE SEPARATOR --------------------------------------

%group hideSeparatorsGroup

	%hook UITableViewCell

	- (void)_updateSeparatorContent
	{

	}

	%end

%end

// -------------------------------------- HIDE ALBUM SHADOW --------------------------------------

%group hideAlbumShadowGroup

	%hook NowPlayingContentView

	- (void)layoutSubviews
	{
		%orig;

		[[self layer] setShadowOpacity: 0];
	}

	%end

%end

void initMusicApp()
{
	@autoreleasepool
	{
		preferences = [MusicPreferences sharedInstance];
		colorizer = [Colorizer sharedInstance];

		isNotchediPhone = [NOTCHED_IPHONES containsObject: getDeviceModel()];

		if([preferences hideAlbumShadow])
			%init(hideAlbumShadowGroup, NowPlayingContentView = NSClassFromString(@"MusicApplication.NowPlayingContentView"));
		
		if([preferences enableCustomRecentlyAddedColumnsNumber] && ![preferences isIpad])
		{
			screenWidth = [[UIScreen mainScreen] _referenceBounds].size.width;
			customRecentlyAddedColumnsNumber = [preferences customRecentlyAddedColumnsNumber];
			%init(customRecentlyAddedColumnsNumberGroup);
		}

		if([preferences hideSeparators])
			%init(hideSeparatorsGroup);

		if([preferences vibrateMusicApp] && ![preferences isIpad]) 
			%init(vibrateMusicAppGroup, TimeSlider = NSClassFromString(@"MusicApplication.PlayerTimeControl"));

		if([preferences hideQueueHUD]) 
			%init(hideQueueHUDGroup, ContextActionsHUDViewController = NSClassFromString(@"MusicApplication.ContextActionsHUDViewController"));

		if([preferences enableMusicAppCustomTint])
			%init(customMusicAppTintColorGroup);

		if([preferences hideKeepOrClearAlert])
			%init(hideKeepOrClearAlertGroup, MusicApplicationTabController = NSClassFromString(@"MusicApplication.TabBarController"));

		if([preferences colorizeMusicApp])
		{
			%init(retrieveArtworkGroup,
				NowPlayingContentView = NSClassFromString(@"MusicApplication.NowPlayingContentView"),
				MiniPlayerViewController = NSClassFromString(@"MusicApplication.MiniPlayerViewController"));

			if([preferences colorizeNowPlayingView])
				%init(colorizeNowPlayingViewGroup,
					NowPlayingViewController = NSClassFromString(@"MusicApplication.NowPlayingViewController"),
					NowPlayingContentView = NSClassFromString(@"MusicApplication.NowPlayingContentView"),
					PlayerTimeControl = NSClassFromString(@"MusicApplication.PlayerTimeControl"),
					ContextualActionsButton = NSClassFromString(@"MusicApplication.ContextualActionsButton"));

			if([preferences colorizeQueueView])
				%init(colorizeQueueViewGroup,
					NowPlayingQueueViewController = NSClassFromString(@"MusicApplication.NowPlayingQueueViewController"),
					NowPlayingQueueHeaderView = NSClassFromString(@"MusicApplication.NowPlayingQueueHeaderView"),
					NowPlayingHistoryHeaderView = NSClassFromString(@"MusicApplication.NowPlayingHistoryHeaderView"),
					QueueGradientView = NSClassFromString(@"MusicApplication.QueueGradientView"));

			if([preferences colorizeMiniPlayerView])
				%init(colorizeMiniPlayerGroup, 
					MiniPlayerViewController = NSClassFromString(@"MusicApplication.MiniPlayerViewController"));

			if([preferences colorizeNowPlayingView] || [preferences colorizeMiniPlayerView])
				%init(sharedViewsGroup,
				NowPlayingTransportButton = NSClassFromString(@"MusicApplication.NowPlayingTransportButton"));
		}
		else if([preferences enableMusicAppNowPlayingViewCustomTint])
		{
			customNowPlayingViewTintColor = [preferences customMusicAppNowPlayingViewTintColor];
			%init(customMusicAppNowPlayingViewTintColorGroup,
			PlayerTimeControl = NSClassFromString(@"MusicApplication.PlayerTimeControl"),
			NowPlayingTransportButton = NSClassFromString(@"MusicApplication.NowPlayingTransportButton"),
			MiniPlayerViewController = NSClassFromString(@"MusicApplication.MiniPlayerViewController"),
			NowPlayingQueueViewController = NSClassFromString(@"MusicApplication.NowPlayingQueueViewController"),
			NowPlayingQueueHeaderView = NSClassFromString(@"MusicApplication.NowPlayingQueueHeaderView"),
			NowPlayingHistoryHeaderView = NSClassFromString(@"MusicApplication.NowPlayingHistoryHeaderView"),
			QueueGradientView = NSClassFromString(@"MusicApplication.QueueGradientView"),
			ContextualActionsButton = NSClassFromString(@"MusicApplication.ContextualActionsButton"));
		}
	}
}