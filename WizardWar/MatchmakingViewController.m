//
//  MatchmakingViewController.m
//  WizardWar
//
//  Created by Sean Hess on 5/17/13.
//  Copyright (c) 2013 The LAB. All rights reserved.
//

#import "MatchmakingViewController.h"
#import "WWDirector.h"
#import "CCScene+Layers.h"
#import "MatchLayer.h"
#import "User.h"
#import "Invite.h"
#import "NSArray+Functional.h"
#import "FirebaseCollection.h"

@interface MatchmakingViewController () <MatchLayerDelegate, FirebaseCollectionDelegate>
@property (nonatomic, strong) CCDirectorIOS * director;
@property (nonatomic, strong) UITableView * tableView;
//@property (nonatomic, strong) NSMutableArray* users;
@property (nonatomic, strong) NSMutableArray* invites;

@property (nonatomic, strong) NSMutableDictionary* users;
@property (nonatomic, strong) FirebaseCollection* usersCollection;
@end

@implementation MatchmakingViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

-(void)loadView {
    [super loadView];
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self.title = @"Matchmaking";
    self.view.backgroundColor = [UIColor redColor];
    
    // init and style the lobby/invites table view
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundView = [[UIView alloc] init];
    self.tableView.backgroundView.backgroundColor = [UIColor colorWithWhite:0.149 alpha:1.000];
    [self.tableView setSeparatorColor:[UIColor clearColor]];
    [self.tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
    
    [self.view layoutIfNeeded];
    
    self.users = [NSMutableDictionary dictionary];
    self.invites = [[NSMutableArray alloc] init];
    [self loadDataFromFirebase];
    
    // check for set nickname
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.nickname = [defaults stringForKey:@"nickname"];
    if (self.nickname == nil) {
        // nickname not set yet so prompt for it
        UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"Nickname" message:@"" delegate:self cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        [av setAlertViewStyle:UIAlertViewStylePlainTextInput];
        [av show];
        av.delegate = self;
    } else {
        [self joinLobby];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)joinMatch:(Invite*)invite playerName:(NSString *)playerName {
    [self startGameWithMatchId:invite.matchID player:self.currentPlayer withAI:nil];
    [self removeInvite:invite];
}

- (Player*)currentPlayer {
    Player * player = [Player new];
    player.name = self.nickname;
    return player;
}

- (void)startGameWithMatchId:(NSString*)matchId player:(Player*)player withAI:(Player*)ai {
    if (self.isInMatch) return;
    self.isInMatch = YES;
    NSAssert(matchId, @"No match id!");
    NSLog(@"joining match %@ with %@", matchId, player.name);
    
    if (!self.director) {
        self.director = [WWDirector directorWithBounds:self.view.bounds];
    }
    
    MatchLayer * match = [[MatchLayer alloc] initWithMatchId:matchId player:player withAI:ai];
    match.delegate = self;
    
    if (self.director.runningScene) {
        [self.director replaceScene:[CCScene sceneWithLayer:match]];
    }
    else {
        [self.director runWithScene:[CCScene sceneWithLayer:match]];
    }
    
    [self.navigationController pushViewController:self.director animated:YES];
}

- (void)doneWithMatch {
    self.isInMatch = NO;
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Alert view delegate

- (void)alertView:(UIAlertView *)alertView willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    self.nickname = [alertView textFieldAtIndex:0].text;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:self.nickname forKey:@"nickname"];
    [self joinLobby];
}

#pragma mark - Firebase stuff

- (void)loadDataFromFirebase
{
    self.firebaseLobby = [[Firebase alloc] initWithUrl:@"https://wizardwar.firebaseIO.com/lobby"];
    
    self.firebaseInvites = [[Firebase alloc] initWithUrl:@"https://wizardwar.firebaseIO.com/invites"];
    
    self.firebaseMatches = [[Firebase alloc] initWithUrl:@"https://wizardwar.firebaseio.com/match"];
    
    // LOBBY
    self.usersCollection = [[FirebaseCollection alloc] initWithNode:self.firebaseLobby type:[User class] dictionary:self.users];
    self.usersCollection.delegate = self;
    
    //INVITES
    [self.firebaseInvites observeEventType:FEventTypeChildAdded withBlock:^(FDataSnapshot *snapshot) {
        Invite * invite = [Invite new];
        [invite setValuesForKeysWithDictionary:snapshot.value];
        // only show invites that apply to you
        if ([invite.invitee isEqualToString:self.nickname] || [invite.inviter isEqualToString:self.nickname ]) {
            [self.invites addObject:invite];
            [self.matchesTableViewController.tableView reloadData];
        }
    }];
    
    [self.firebaseInvites observeEventType:FEventTypeChildRemoved withBlock:^(FDataSnapshot *snapshot) {
        Invite * removedInvite = [Invite new];
        [removedInvite setValuesForKeysWithDictionary:snapshot.value];
        [self removeInvite:removedInvite];
    }];
    
}

- (NSArray*)lobbyNames {
    return [[self.users allKeys] filter:^BOOL(NSString * name) {
        return ![name isEqualToString:self.nickname];
    }];
}

- (void)didAddChild:(id)object {
    [self.tableView reloadData];
}

- (void)didRemoveChild:(id)object {
    [self.tableView reloadData];
}

- (void)didUpdateChild:(id)object {
    [self.tableView reloadData];
}

-(void)removeInvite:(Invite*)removedInvite {
    self.invites = [[self.invites filter:^BOOL(Invite * invite) {
        return ![invite.inviteId isEqualToString:removedInvite.inviteId];
    }] mutableCopy];
    [self.matchesTableViewController.tableView reloadData];
}

- (void)joinLobby
{
    User * user = [User new];
    user.name = self.nickname;
    [self.usersCollection addObject:user withName:self.nickname];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return [self.invites count];
    } else {
        return [self.lobbyNames count];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *view = [[UIView alloc] init];
    if (section == 0) {
//        UIImage *image = [UIImage imageNamed:@"navbar-logo.png"];
//        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
//        imageView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
//        CGRect frame = imageView.frame;
//        frame.origin.y = 10;
//        imageView.frame = frame;
//        [view addSubview:imageView];
    } else {
        UIImage *image = [UIImage imageNamed:@"wizard-lobby.png"];
        UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
        CGRect size = self.view.bounds;
        imageView.frame = CGRectMake(((size.size.width - 159)/ 2),20,159,20);
        [view addSubview:imageView];
    }
    return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        return [self tableView:tableView inviteCellForRowAtIndexPath:indexPath];
    } else {
        return [self tableView:tableView userCellForRowAtIndexPath:indexPath];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 0) {
        return 0;
    } else {
        return 60;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 44;
}

-(UITableViewCell*)tableView:(UITableView *)tableView userCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"UserCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.backgroundColor = [UIColor colorWithWhite:0.784 alpha:1.000];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.149 alpha:1.000];
    }
    
    NSString * userKey = [self.lobbyNames objectAtIndex:indexPath.row];
    User* user = [self.users objectForKey:userKey];
    
    if ([user.name isEqualToString:self.nickname]) {
        cell.textLabel.text = @"Practice Game";
    }
    else {
        cell.textLabel.text = user.name;
    }
    return cell;
}

-(UITableViewCell*)tableView:(UITableView *)tableView inviteCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"InviteCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    Invite * invite = [self.invites objectAtIndex:indexPath.row];
    if (invite.inviter == self.nickname) {
        cell.textLabel.text = [NSString stringWithFormat:@"You invited %@", invite.invitee];
        cell.userInteractionEnabled = NO;
        cell.backgroundColor = [UIColor colorWithRed:0.827 green:0.820 blue:0.204 alpha:1.000];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.149 alpha:1.000];
    }
    else {
        cell.textLabel.text = [NSString stringWithFormat:@"%@ challenges you!", invite.inviter];
        cell.userInteractionEnabled = YES;
        cell.backgroundColor = [UIColor colorWithRed:0.490 green:0.706 blue:0.275 alpha:1.000];
        cell.textLabel.textColor = [UIColor colorWithWhite:0.149 alpha:1.000];
    }
    
    return cell;
}

#pragma mark - Table view delegate

-(void)createInvite:(User*)user {
    Invite * invite = [Invite new];
    invite.inviter = self.nickname;
    invite.invitee = user.name;
    
    Firebase * inviteNode = [self.firebaseInvites childByAppendingPath:invite.inviteId];
    [inviteNode setValue:invite.toObject];
    [inviteNode onDisconnectRemoveValue];
        
    // listen to the created invite for acceptance
    Firebase * matchIDNode = [inviteNode childByAppendingPath:@"matchID"];
    NSLog(@"MATCH ID NODE %@", matchIDNode);
    [matchIDNode observeEventType:FEventTypeValue withBlock:^(FDataSnapshot *snapshot) {
        if (snapshot.value != [NSNull null]) {
            NSLog(@"Inivite Changed %@", snapshot.value);
            // match has begun! join up
            self.matchID = snapshot.value;
            invite.matchID = self.matchID;
            [self joinMatch:invite playerName:self.nickname];
        }
    }];
}

-(void)selectInvite:(Invite*)invite {
    // start the match!
    NSString * matchID = [NSString stringWithFormat:@"%i", arc4random()];
    invite.matchID = matchID;
    
    Firebase* inviteNode = [self.firebaseInvites childByAppendingPath:invite.inviteId];
    [inviteNode setValue:invite.toObject];
    [inviteNode onDisconnectRemoveValue];
    [self joinMatch:invite playerName:self.nickname];
}

-(void)startPracticeGame {
    NSString * matchID = [NSString stringWithFormat:@"%i", arc4random()];
    Player * ai = [Player new];
    ai.name = @"zzzai";
    [self startGameWithMatchId:matchID player:self.currentPlayer withAI:ai];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        Invite * invite = [self.invites objectAtIndex:indexPath.row];
        [self selectInvite:invite];
    } else {
        NSString* userKey = [self.lobbyNames objectAtIndex:indexPath.row];
        User* user = [self.users objectForKey:userKey];
        if ([user.name isEqualToString:self.nickname])
            [self startPracticeGame];
        else
            [self createInvite:user];
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
