//
//  AppDelegate.h
//  AudioZoom
//
//  Created by Danh Nguyen on 4/7/18.
//  Copyright © 2018 Danh Nguyen. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong) NSPersistentContainer *persistentContainer;

- (void)saveContext;


@end

