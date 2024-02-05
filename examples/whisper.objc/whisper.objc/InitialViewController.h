//
//  InitialViewController.h
//  my-order-genie
//
//  Created by 오장민 on 2/3/24.
//

#import <UIKit/UIKit.h>

#import "CommonTypes.h"


@interface InitialViewController : UIViewController
{
    StateInp stateInp;
}

@property (strong, nonatomic) UIActivityIndicatorView *loadingIndicator;

@end

//NS_ASSUME_NONNULL_END
