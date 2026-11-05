#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/wait.h>
#import <string.h>
#import <unistd.h>

extern char **environ;

static NSString *RunCommand(NSString *command, NSString *password) {
    int out[2], in[2];
    if (pipe(out) != 0) return @"pipe failed";
    if (pipe(in) != 0) return @"pipe failed";

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, out[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&fa, out[1], STDERR_FILENO);
    posix_spawn_file_actions_adddup2(&fa, in[0], STDIN_FILENO);
    posix_spawn_file_actions_addclose(&fa, out[0]);
    posix_spawn_file_actions_addclose(&fa, in[1]);

    const char *cmd = [command UTF8String];
    char *argv[] = { "/usr/bin/sudo", "-S", "-p", "", "/bin/bash", "-c", (char *)cmd, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/usr/bin/sudo", &fa, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&fa);

    if (rc != 0) {
        close(out[0]); close(out[1]); close(in[0]); close(in[1]);
        return [NSString stringWithFormat:@"spawn failed: %d", rc];
    }

    close(out[1]);
    close(in[0]);

    NSString *pw = [password stringByAppendingString:@"\n"];
    write(in[1], pw.UTF8String, pw.length);
    close(in[1]);

    NSMutableData *data = [NSMutableData data];
    char buf[4096];
    ssize_t n;
    while ((n = read(out[0], buf, sizeof(buf))) > 0)
        [data appendBytes:buf length:(NSUInteger)n];
    close(out[0]);

    int status = 0;
    waitpid(pid, &status, 0);

    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return s ?: @"";
}

static NSArray *InstalledApps(void) {
    Class WS = NSClassFromString(@"LSApplicationWorkspace");
    if (!WS) return @[];
    id workspace = [WS performSelector:@selector(defaultWorkspace)];
    if (!workspace) return @[];
    NSArray *all = [workspace performSelector:@selector(allInstalledApplications)];
    if (!all) return @[];

    NSMutableArray *out = [NSMutableArray array];
    for (id app in all) {
        NSString *bid = [app performSelector:@selector(bundleIdentifier)];
        NSString *name = [app performSelector:@selector(localizedName)];
        if (!bid.length || !name.length) continue;
        [out addObject:@{@"bid": bid, @"name": name}];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return out;
}

@interface LogViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) NSString *logText;
@end

@implementation LogViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"DumpBox 日志";

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.textView.text = self.logText ?: @"";
    [self.view addSubview:self.textView];
}
@end

@interface ListViewController : UITableViewController
@property (nonatomic, strong) NSArray *apps;
@end

@implementation ListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DumpBox";
    self.apps = InstalledApps();
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                             target:self
                             action:@selector(reload)];
}

- (void)reload {
    self.apps = InstalledApps();
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.apps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellId = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellId];
    }
    NSDictionary *app = self.apps[indexPath.row];
    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = app[@"bid"];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = self.apps[indexPath.row];
    [self runDump:app[@"bid"]];
}

- (void)runDump:(NSString *)bid {
    LogViewController *vc = [[LogViewController alloc] init];
    vc.title = bid;
    NSString *startMsg = [NSString stringWithFormat:@"开始砸壳 %@\n\n", bid];
    vc.logText = startMsg;
    [self.navigationController pushViewController:vc animated:YES];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:@"" forKey:@"result"];
    [ud setObject:@"NEW" forKey:@"status"];
    [ud setObject:bid forKey:@"request"];
    [ud synchronize];

    vc.logText = [startMsg stringByAppendingString:@"已提交到 root 队列，等待执行...\n"];
    vc.textView.text = vc.logText;

    NSString *resultPath = @"/var/mobile/Documents/DumpBox/result";
    NSString *plistPath = @"/var/mobile/Library/Preferences/com.dumpbox.app.plist";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *latest = vc.logText;
        for (int i = 0; i < 600; i++) {
            NSString *status = @"";
            NSString *result = [NSString stringWithContentsOfFile:resultPath
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil];
            if (!result.length) {
                NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:plistPath];
                if (d) {
                    status = [d[@"status"] description] ?: @"";
                    result = [d[@"result"] description] ?: @"";
                }
            } else {
                status = [result rangeOfString:@"DONE"].location != NSNotFound ? @"DONE" : @"RUNNING";
            }
            if (result.length) {
                latest = result;
                if (i % 3 == 0 || [status isEqualToString:@"DONE"]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        vc.textView.text = latest;
                    });
                }
            }
            if ([status isEqualToString:@"DONE"]) break;
            sleep(1);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            vc.textView.text = latest;
        });
    });
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    ListViewController *list = [[ListViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end
