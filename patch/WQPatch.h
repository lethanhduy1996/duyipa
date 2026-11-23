#import <UIKit/UIKit.h>

@interface WQPatchViewController : UITableViewController <UIDocumentPickerDelegate>
- (instancetype)initWithImportFilePath:(NSString *)path;
- (instancetype)initWithImportURL:(NSURL *)url;
@end
