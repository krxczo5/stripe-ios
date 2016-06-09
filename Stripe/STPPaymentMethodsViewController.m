//
//  STPSourceListViewController.m
//  Stripe
//
//  Created by Jack Flintermann on 1/12/16.
//  Copyright © 2016 Stripe, Inc. All rights reserved.
//

#import "STPPaymentMethodsViewController.h"
#import "STPBackendAPIAdapter.h"
#import "STPAPIClient.h"
#import "STPToken.h"
#import "STPCard.h"
#import "NSArray+Stripe_BoundSafe.h"
#import "UINavigationController+Stripe_Completion.h"
#import "UIViewController+Stripe_ParentViewController.h"
#import "STPAddCardViewController.h"
#import "STPApplePayPaymentMethod.h"
#import "STPPaymentContext.h"
#import "STPPaymentMethodTuple.h"
#import "STPPaymentActivityIndicatorView.h"
#import "UIImage+Stripe.h"
#import "NSString+Stripe_CardBrands.h"
#import "UITableViewCell+Stripe_Borders.h"
#import "STPPaymentMethodsViewController+Private.h"
#import "STPPaymentContext+Private.h"
#import "UIBarButtonItem+Stripe.h"
#import "UIViewController+Stripe_Promises.h"
#import "STPPaymentConfiguration+Private.h"
#import "STPPaymentMethodsInternalViewController.h"
#import "STPAddCardViewController.h"
#import "UIViewController+Stripe_NavigationItemProxy.h"

@interface STPPaymentMethodsViewController()<STPPaymentMethodsInternalViewControllerDelegate>

@property(nonatomic)STPPaymentConfiguration *configuration;
@property(nonatomic)id<STPBackendAPIAdapter> apiAdapter;
@property(nonatomic)STPAPIClient *apiClient;
@property(nonatomic)STPPromise<STPPaymentMethodTuple *> *loadingPromise;
@property(nonatomic)NSArray<id<STPPaymentMethod>> *paymentMethods;
@property(nonatomic)id<STPPaymentMethod> selectedPaymentMethod;
@property(nonatomic, weak)STPPaymentActivityIndicatorView *activityIndicator;
@property(nonatomic, weak)UIViewController *internalViewController;
@property(nonatomic)UIBarButtonItem *backItem;
@property(nonatomic)UIBarButtonItem *cancelItem;
@property(nonatomic)BOOL loading;

@end

@implementation STPPaymentMethodsViewController

- (instancetype)initWithPaymentContext:(STPPaymentContext *)paymentContext {
    return [self initWithConfiguration:paymentContext.configuration
                            apiAdapter:paymentContext.apiAdapter
                        loadingPromise:paymentContext.currentValuePromise
                              delegate:paymentContext];
}


- (instancetype)initWithConfiguration:(STPPaymentConfiguration *)configuration
                           apiAdapter:(id<STPBackendAPIAdapter>)apiAdapter
                             delegate:(id<STPPaymentMethodsViewControllerDelegate>)delegate {
    STPPromise<STPPaymentMethodTuple *> *promise = [STPPromise new];
    [apiAdapter retrieveCustomerSources:^(NSString * _Nullable defaultSourceID, NSArray<id<STPSource>> * _Nullable sources, NSError * _Nullable error) {
        if (error) {
            [promise fail:error];
        } else {
            STPCard *selectedCard;
            NSMutableArray<STPCard *> *cards = [NSMutableArray array];
            for (id<STPSource> source in sources) {
                if ([source isKindOfClass:[STPCard class]]) {
                    STPCard *card = (STPCard *)source;
                    [cards addObject:card];
                    if ([card.stripeID isEqualToString:defaultSourceID]) {
                        selectedCard = card;
                    }
                }
            }
            STPCardTuple *cardTuple = [STPCardTuple tupleWithSelectedCard:selectedCard cards:cards];
            STPPaymentMethodTuple *tuple = [STPPaymentMethodTuple tupleWithCardTuple:cardTuple
                                                                     applePayEnabled:configuration.applePayEnabled];
            [promise succeed:tuple];
        }
    }];
    return [self initWithConfiguration:configuration apiAdapter:apiAdapter loadingPromise:promise delegate:delegate];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    STPPaymentActivityIndicatorView *activityIndicator = [STPPaymentActivityIndicatorView new];
    activityIndicator.animating = YES;
    [self.view addSubview:activityIndicator];
    self.activityIndicator = activityIndicator;
    
    self.navigationItem.title = NSLocalizedString(@"Choose Payment", nil);
    self.backItem = [UIBarButtonItem stp_backButtonItemWithTitle:NSLocalizedString(@"Back", nil) style:UIBarButtonItemStylePlain target:self action:@selector(cancel:)];
    self.cancelItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel:)];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Back", nil) style:UIBarButtonItemStylePlain target:nil action:nil];
    __weak typeof(self) weakself = self;
    [self.loadingPromise onSuccess:^(STPPaymentMethodTuple *tuple) {
        UIViewController *internal;
        if (tuple.paymentMethods.count > 0) {
            internal = [[STPPaymentMethodsInternalViewController alloc] initWithConfiguration:weakself.configuration paymentMethodTuple:tuple delegate:weakself];
        } else {
            internal = [[STPAddCardViewController alloc] initWithConfiguration:weakself.configuration completion:^(STPToken * _Nullable token, STPErrorBlock  _Nonnull tokenCompletion) {
                [weakself internalViewControllerDidCreateToken:token completion:tokenCompletion];
            }];
        }
        internal.stp_navigationItemProxy = self.navigationItem;
        [weakself addChildViewController:internal];
        internal.view.alpha = 0;
        [weakself.view insertSubview:internal.view belowSubview:weakself.activityIndicator];
        [weakself.view addSubview:internal.view];
        internal.view.frame = weakself.view.bounds;
        [internal didMoveToParentViewController:weakself];
        [UIView animateWithDuration:0.2 animations:^{
            weakself.activityIndicator.alpha = 0;
            internal.view.alpha = 1;
            self.navigationItem.title = internal.stp_navigationItemProxy.title;
        } completion:^(__unused BOOL finished) {
            weakself.activityIndicator.animating = NO;
        }];
        [self.navigationItem setRightBarButtonItem:internal.stp_navigationItemProxy.rightBarButtonItem animated:YES];
    }];
    self.loading = YES;
    [self updateAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.leftBarButtonItem = [self stp_isRootViewControllerOfNavigationController] ? self.cancelItem : self.backItem;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.activityIndicator.center = self.view.center;
    self.internalViewController.view.frame = self.view.bounds;
}

- (void)updateAppearance {
    [self.navigationItem.backBarButtonItem stp_setTheme:self.configuration.theme];
    [self.backItem stp_setTheme:self.configuration.theme];
    [self.cancelItem stp_setTheme:self.configuration.theme];
    self.view.backgroundColor = self.configuration.theme.primaryBackgroundColor;
}

- (void)cancel:(__unused id)sender {
    [self.delegate paymentMethodsViewControllerDidFinish:self];
}

- (void)finishWithPaymentMethod:(id<STPPaymentMethod>)paymentMethod {
    if ([paymentMethod isKindOfClass:[STPCard class]]) {
        [self.apiAdapter selectDefaultCustomerSource:(STPCard *)paymentMethod completion:^(__unused NSError *error) {
        }];
    }
    [self.delegate paymentMethodsViewController:self didSelectPaymentMethod:paymentMethod];
    [self.delegate paymentMethodsViewControllerDidFinish:self];
}

- (void)internalViewControllerDidSelectPaymentMethod:(id<STPPaymentMethod>)paymentMethod {
    [self finishWithPaymentMethod:paymentMethod];
}

- (void)internalViewControllerDidCreateToken:(STPToken *)token completion:(STPErrorBlock)completion {
    [self.apiAdapter attachSourceToCustomer:token completion:^(NSError * _Nullable error) {
        completion(error);
        if (!error) {
            [self finishWithPaymentMethod:token.card];
        }
    }];
}

@end

@implementation STPPaymentMethodsViewController (Private)

- (instancetype)initWithConfiguration:(STPPaymentConfiguration *)configuration
                           apiAdapter:(id<STPBackendAPIAdapter>)apiAdapter
                       loadingPromise:(STPPromise<STPPaymentMethodTuple *> *)loadingPromise
                             delegate:(id<STPPaymentMethodsViewControllerDelegate>)delegate {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _configuration = configuration;
        _apiClient = [[STPAPIClient alloc] initWithPublishableKey:configuration.publishableKey];
        _apiAdapter = apiAdapter;
        _loadingPromise = loadingPromise;
        _delegate = delegate;
        __weak typeof(self) weakself = self;
        [loadingPromise onSuccess:^(STPPaymentMethodTuple *tuple) {
            weakself.paymentMethods = tuple.paymentMethods;
            weakself.selectedPaymentMethod = tuple.selectedPaymentMethod;
        }];
        [[[self.stp_didAppearPromise voidFlatMap:^STPPromise * _Nonnull{
            return loadingPromise;
        }] onSuccess:^(STPPaymentMethodTuple *tuple) {
            if (tuple.selectedPaymentMethod) {
                [weakself.delegate paymentMethodsViewController:weakself
                                         didSelectPaymentMethod:tuple.selectedPaymentMethod];
            }
        }] onFailure:^(NSError *error) {
            [weakself.delegate paymentMethodsViewController:weakself didFailToLoadWithError:error];
        }];
    }
    return self;
}

@end