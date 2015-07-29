//
//  TSMarkdownParser.m
//  TSMarkdownParser
//
//  Created by Tobias Sundstrand on 14-08-30.
//  Copyright (c) 2014 Computertalk Sweden. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TSMarkdownParser.h"
@interface TSExpressionBlockPair : NSObject

@property (nonatomic, strong) NSRegularExpression *regularExpression;
@property (nonatomic, strong) TSMarkdownParserMatchBlock block;

+ (TSExpressionBlockPair *)pairWithRegularExpression:(NSRegularExpression *)regularExpression block:(TSMarkdownParserMatchBlock)block;

@end

@implementation TSExpressionBlockPair

+ (TSExpressionBlockPair *)pairWithRegularExpression:(NSRegularExpression *)regularExpression block:(TSMarkdownParserMatchBlock)block {
    TSExpressionBlockPair *pair = [TSExpressionBlockPair new];
    pair.regularExpression = regularExpression;
    pair.block = block;
    return pair;
}

@end

@interface TSMarkdownParser ()

@property (nonatomic, strong) NSMutableArray *parsingPairs;
@property (nonatomic, copy) void (^paragraphParsingBlock)(NSMutableAttributedString *attributedString);

@end

@implementation TSMarkdownParser

- (instancetype)init {
    self = [super init];
    if(self) {
        _parsingPairs = [NSMutableArray array];
        _paragraphFont = [UIFont systemFontOfSize:12];
        _strongFont = [UIFont boldSystemFontOfSize:12];
        _emphasisFont = [UIFont italicSystemFontOfSize:12];
        _h1Font = [UIFont boldSystemFontOfSize:23];
        _h2Font = [UIFont boldSystemFontOfSize:21];
        _h3Font = [UIFont boldSystemFontOfSize:19];
        _h4Font = [UIFont boldSystemFontOfSize:17];
        _h5Font = [UIFont boldSystemFontOfSize:15];
        _h6Font = [UIFont boldSystemFontOfSize:13];
        _linkColor = [UIColor blueColor];
        _linkUnderlineStyle = @(NSUnderlineStyleSingle);
        _defaultTextColor = [UIColor blackColor];
    }
    return self;
}

+ (TSMarkdownParser *)standardParser {

    TSMarkdownParser *defaultParser = [TSMarkdownParser new];

    __weak TSMarkdownParser *weakParser = defaultParser;
    
    [defaultParser addImageParsingWithImageFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        
    }                       alternativeTextFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        
    }];
    
    [defaultParser addParagraphParsingWithFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.paragraphFont
                                 range:range];
    }];
    
    [defaultParser addStrongParsingWithFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.strongFont
                                 range:range];
    }];

    [defaultParser addEmphasisParsingWithFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.emphasisFont
                                 range:range];
    }];

    [defaultParser addListParsingWithFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString replaceCharactersInRange:range withString:@"•\t"];
    }];

    [defaultParser addLinkParsingWithFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {

        [attributedString addAttribute:NSUnderlineStyleAttributeName
                                 value:weakParser.linkUnderlineStyle
                                 range:range];
        [attributedString addAttribute:NSForegroundColorAttributeName
                                 value:weakParser.linkColor
                                 range:range];
    }];

    [defaultParser addHeaderParsingWithLevel:1 formattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.h1Font
                                 range:range];
    }];

    [defaultParser addHeaderParsingWithLevel:2 formattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.h2Font
                                 range:range];
    }];

    [defaultParser addHeaderParsingWithLevel:3 formattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.h3Font
                                 range:range];
    }];

    [defaultParser addHeaderParsingWithLevel:4 formattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.h4Font
                                 range:range];
    }];

    [defaultParser addHeaderParsingWithLevel:5 formattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.h5Font
                                 range:range];
    }];

    [defaultParser addHeaderParsingWithLevel:6 formattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        [attributedString addAttribute:NSFontAttributeName
                                 value:weakParser.h6Font
                                 range:range];
    [attributedString deleteCharactersInRange:NSMakeRange(range.location+7, range.length-7)];// 6 hashes plus space
    }];

    
    [defaultParser addCenterFormattingBlock:^(NSMutableAttributedString *attributedString, NSRange range) {
        NSMutableParagraphStyle *paragraphStyle = NSMutableParagraphStyle.new;
        paragraphStyle.alignment                = NSTextAlignmentCenter;
        
        [attributedString addAttribute:NSParagraphStyleAttributeName
                                 value:paragraphStyle
                                 range:range];
    }];
    
   
   

    return defaultParser;
}

static NSString *const TSMarkdownStrongRegex    = @"([\\*|_]{2}).+?\\1";
static NSString *const TSMarkdownEmRegex        = @"(?<=[^\\*_]|^)(\\*|_)[^\\*_]+[^\\*_\\n]+(\\*|_)(?=[^\\*_]|$)";
static NSString *const TSMarkdownListRegex      = @"^(\\*|\\+)[^\\*].+$";
static NSString *const TSMarkdownLinkRegex      = @"(?<!\\!)\\[.*?\\]\\([^\\)]*\\)";
static NSString *const TSMarkdownImageRegex     = @"\\!\\[.*?\\]\\(\\S*\\)";
static NSString *const TSMarkdownHeaderRegex    = @"^(#{%i}\\s*)(?!#).*$";
static NSString *const TSMarkdownCenterRegex    = @"(->){1}.*(<-){1}";

- (NSTextCheckingResult *) getH6Range:(NSString *)rawMarkDown
{
    NSString *headerRegex = [NSString stringWithFormat:TSMarkdownHeaderRegex, 6];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:headerRegex options:NSRegularExpressionCaseInsensitive | NSRegularExpressionAnchorsMatchLines error:nil];
    
    NSTextCheckingResult *match = [regex firstMatchInString:rawMarkDown options:0 range:NSMakeRange(0, rawMarkDown.length)];
    return match;
}
- (void)addParagraphParsingWithFormattingBlock:(void(^)(NSMutableAttributedString *attributedString, NSRange range))formattingBlock {
    self.paragraphParsingBlock = ^(NSMutableAttributedString *attributedString) {
        
        formattingBlock(attributedString, NSMakeRange(0, attributedString.length));
    };
}

- (void)addStrongParsingWithFormattingBlock:(void(^)(NSMutableAttributedString *attributedString, NSRange range))formattingBlock {
    NSRegularExpression *boldParsing = [NSRegularExpression regularExpressionWithPattern:TSMarkdownStrongRegex options:NSRegularExpressionCaseInsensitive error:nil];

    [self addParsingRuleWithRegularExpression:boldParsing withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {
// add escape character and escape escape character to the mix.
      if(![TSMarkdownParser isEscaped:match attribString:attributedString matchLength:2])
       {
           formattingBlock(attributedString, match.range);
           int deletedBackslashCount = [TSMarkdownParser deleteEscapedBackslash:match attribString:attributedString];
           [attributedString deleteCharactersInRange:NSMakeRange(match.range.location-(deletedBackslashCount>0?1:0), 2)];
           [attributedString deleteCharactersInRange:NSMakeRange(match.range.location+match.range.length-4 - (deletedBackslashCount >1?deletedBackslashCount:deletedBackslashCount >0?deletedBackslashCount:0), 2)];
       }
    }];
}
+(int) deleteEscapedBackslash:(NSTextCheckingResult *)match attribString:(NSMutableAttributedString *)attributedString
{
    int deletedBackslashCount = 0;
    // delete escaped backslashes
    if([[attributedString.string substringWithRange:NSMakeRange(match.range.location -2, 1)] compare:@"\\"] == 0)
    {
        [attributedString deleteCharactersInRange:NSMakeRange(match.range.location-2, 1)];
        deletedBackslashCount++;
    }
    if([[attributedString.string substringWithRange:NSMakeRange(match.range.location+match.range.length-3-deletedBackslashCount,1)] compare:@"\\"] == 0)
    {
        [attributedString deleteCharactersInRange:NSMakeRange(match.range.location+match.range.length-3-deletedBackslashCount, 1)];
        deletedBackslashCount++;
    }
    return deletedBackslashCount;
}
+(BOOL) isEscaped:(NSTextCheckingResult *)match attribString:(NSMutableAttributedString *)attributedString matchLength:(NSUInteger) tokenLength
{
    if( ((match.range.location > 0 && [[attributedString.string substringWithRange:NSMakeRange(match.range.location -1, 1)] compare:@"\\"] == 0) &&
         (match.range.location > 1 && [[attributedString.string substringWithRange:NSMakeRange(match.range.location -2, 1)] compare:@"\\"] != 0)) ||
       ((match.range.location+match.range.length-4 > 0 && [[attributedString.string substringWithRange:NSMakeRange(match.range.location+match.range.length-5, 1)] compare:@"\\"] == 0) &&
        (match.range.location > 1 && [[attributedString.string substringWithRange:NSMakeRange(match.range.location+match.range.length-6,1)] compare:@"\\"] != 0)))
    {
        // if preceded by a backslash and backslash not escaped
        NSUInteger location = match.range.location -1;
        NSUInteger location2 = match.range.location+match.range.length-tokenLength -1;
        
        NSString *locS = [attributedString.string substringWithRange:NSMakeRange(location, 1)];
        NSString *locS1 = [attributedString.string substringWithRange:NSMakeRange(location2, 1)];
        if( match.range.location > 0 && [[attributedString.string substringWithRange:NSMakeRange(location, 1)] compare:@"\\"] == 0)
        {
            [attributedString deleteCharactersInRange:NSMakeRange(match.range.location-1, 1)];
            location2--;
        }
        if(location2 > 0 && [[attributedString.string substringWithRange:NSMakeRange(location2, 1)] compare:@"\\"] == 0)
        {
            [attributedString deleteCharactersInRange:NSMakeRange(location2, 1)];
        }
        return YES;
    }
    return NO;
}
- (void)addEmphasisParsingWithFormattingBlock:(TSMarkdownParserFormattingBlock)formattingBlock {
    NSRegularExpression *emphasisParsing = [NSRegularExpression regularExpressionWithPattern:TSMarkdownEmRegex options:NSRegularExpressionCaseInsensitive error:nil];

    [self addParsingRuleWithRegularExpression:emphasisParsing withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {
        
        if(![TSMarkdownParser isEscaped:match attribString:attributedString matchLength:1])
        {
            formattingBlock(attributedString, match.range);
            int deletedBackslashCount = [TSMarkdownParser deleteEscapedBackslash:match attribString:attributedString];
            [attributedString deleteCharactersInRange:NSMakeRange(match.range.location-(deletedBackslashCount>0?1:0), 1)];
            [attributedString deleteCharactersInRange:NSMakeRange(match.range.location+match.range.length-2 - (deletedBackslashCount >1?deletedBackslashCount:deletedBackslashCount >0?deletedBackslashCount:0), 1)];
        }
    }];
}

- (void)addListParsingWithFormattingBlock:(TSMarkdownParserFormattingBlock)formattingBlock {
    NSRegularExpression *listParsing = [NSRegularExpression regularExpressionWithPattern:TSMarkdownListRegex options:NSRegularExpressionCaseInsensitive|NSRegularExpressionAnchorsMatchLines error:nil];
    [self addParsingRuleWithRegularExpression:listParsing withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {
        formattingBlock(attributedString, NSMakeRange(match.range.location, 1));
    }];

}

- (void)addLinkParsingWithFormattingBlock:(TSMarkdownParserFormattingBlock)formattingBlock {
    NSRegularExpression *linkParsing = [NSRegularExpression regularExpressionWithPattern:TSMarkdownLinkRegex options:NSRegularExpressionCaseInsensitive error:nil];

    [self addParsingRuleWithRegularExpression:linkParsing withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {

        NSUInteger linkStartInResult = [attributedString.string rangeOfString:@"(" options:NSBackwardsSearch range:match.range].location;
        NSRange linkRange = NSMakeRange(linkStartInResult, match.range.length+match.range.location-linkStartInResult-1);
        NSString *linkURLString = [attributedString.string substringWithRange:NSMakeRange(linkRange.location+1, linkRange.length-1)];
        NSURL *url = [NSURL URLWithString:linkURLString];

        NSUInteger linkTextEndLocation = [attributedString.string rangeOfString:@"]" options:0 range:match.range].location;
        NSRange linkTextRange = NSMakeRange(match.range.location, linkTextEndLocation-match.range.location-1);

        [attributedString deleteCharactersInRange:NSMakeRange(match.range.location, 1)];
        [attributedString deleteCharactersInRange:NSMakeRange(linkRange.location-2, linkRange.length+2)];

        [attributedString addAttribute:NSLinkAttributeName
                                 value:url
                                 range:linkTextRange];

        formattingBlock(attributedString, linkTextRange);

    }];
}

- (void)addHeaderParsingWithLevel:(int)header formattingBlock:(TSMarkdownParserFormattingBlock)formattingBlock {
    NSString *headerRegex = [NSString stringWithFormat:TSMarkdownHeaderRegex, header];
    NSRegularExpression *headerExpression = [NSRegularExpression regularExpressionWithPattern:headerRegex options:NSRegularExpressionCaseInsensitive | NSRegularExpressionAnchorsMatchLines error:nil];
    [self addParsingRuleWithRegularExpression:headerExpression withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {
        formattingBlock(attributedString, match.range);
        NSRange rr = [match rangeAtIndex:1];
        [attributedString deleteCharactersInRange:[match rangeAtIndex:1]];
    }];
}

- (void)addImageParsingWithImageFormattingBlock:(TSMarkdownParserFormattingBlock)formattingBlock alternativeTextFormattingBlock:(TSMarkdownParserFormattingBlock)alternativeFormattingBlock {
    NSRegularExpression *headerExpression = [NSRegularExpression regularExpressionWithPattern:TSMarkdownImageRegex options:NSRegularExpressionCaseInsensitive error:nil];
    [self addParsingRuleWithRegularExpression:headerExpression withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {
        NSUInteger imagePathStart = [attributedString.string rangeOfString:@"(" options:0 range:match.range].location;
        NSRange linkRange = NSMakeRange(imagePathStart, match.range.length+match.range.location- imagePathStart -1);
        NSString *imagePath = [attributedString.string substringWithRange:NSMakeRange(linkRange.location+1, linkRange.length-1)];
        UIImage *image = [UIImage imageNamed:imagePath];
        //imagePath can be both url or just a filename
        if(image == nil)
        {
            // parse out to check if image filename is in local bundle otherwise go remote to fetch it.
            NSURL *url = [NSURL URLWithString:imagePath];
            NSString *parsedFileName = url.lastPathComponent;
            NSString *imageName = [parsedFileName substringToIndex:(parsedFileName.length - (url.pathExtension.length == 0?0:url.pathExtension.length+1)) ];
            image = [UIImage imageNamed:imageName];
            if(image == nil)
            {
                NSData *imageData = [NSData dataWithContentsOfURL:url];
                image = [UIImage imageWithData:imageData];
            }
        }
        if(image){
            [attributedString deleteCharactersInRange:match.range];
            NSTextAttachment *imageAttachment = [NSTextAttachment new];
            imageAttachment.image = image;
            imageAttachment.bounds = CGRectMake(0, -5, image.size.width, image.size.height);
            NSAttributedString *imgStr = [NSAttributedString attributedStringWithAttachment:imageAttachment];
            NSRange imageRange = NSMakeRange(match.range.location, 1);
            [attributedString insertAttributedString:imgStr atIndex:match.range.location];
            if(formattingBlock) {
                formattingBlock(attributedString, imageRange);
            }
        } else {
            NSUInteger linkTextEndLocation = [attributedString.string rangeOfString:@"]" options:0 range:match.range].location;
            NSRange linkTextRange = NSMakeRange(match.range.location+2, linkTextEndLocation-match.range.location-2);
            NSString *alternativeText = [attributedString.string substringWithRange:linkTextRange];
            if(alternativeFormattingBlock) {
                alternativeFormattingBlock(attributedString, match.range);
            }
            [attributedString replaceCharactersInRange:match.range withString:alternativeText];
        }
    }];
}
- (void)addCenterFormattingBlock:(TSMarkdownParserFormattingBlock)formattingBlock{

    NSRegularExpression *centerParsing = [NSRegularExpression regularExpressionWithPattern:TSMarkdownCenterRegex options:NSRegularExpressionCaseInsensitive error:nil];
    [self addParsingRuleWithRegularExpression:centerParsing withBlock:^(NSTextCheckingResult *match, NSMutableAttributedString *attributedString) {
        formattingBlock(attributedString, match.range);
        [attributedString deleteCharactersInRange:NSMakeRange(match.range.location, 2)];
        [attributedString deleteCharactersInRange:NSMakeRange(match.range.location+match.range.length-4, 2)];     }];
    
}
- (void)addParsingRuleWithRegularExpression:(NSRegularExpression *)regularExpression withBlock:(TSMarkdownParserMatchBlock)block {
    @synchronized (self) {
        [self.parsingPairs addObject:[TSExpressionBlockPair pairWithRegularExpression:regularExpression block:block]];
    }
}

- (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    NSMutableAttributedString *mutableAttributedString = [[NSMutableAttributedString alloc] initWithString:markdown];
    [mutableAttributedString addAttribute:NSForegroundColorAttributeName value:self.defaultTextColor range:NSMakeRange(0, mutableAttributedString.length)];
    if ( self.paragraphParsingBlock ) {
        self.paragraphParsingBlock(mutableAttributedString);
    }

    @synchronized (self) {
        for (TSExpressionBlockPair *expressionBlockPair in self.parsingPairs) {
            NSTextCheckingResult *match;
            NSRange startRange = NSMakeRange(0, mutableAttributedString.string.length);
            while((match = [expressionBlockPair.regularExpression firstMatchInString:mutableAttributedString.string options:0 range:startRange])){
                NSRange matchRange = match.range;
                    // if not \ escape then resume search after matched location, otherwise we may try to reconsume escaped characters.
                    NSUInteger originalLength = mutableAttributedString.length;
                    expressionBlockPair.block(match, mutableAttributedString);
                    NSUInteger consumed =  originalLength - mutableAttributedString.length;
                    NSUInteger start = (matchRange.location + matchRange.length) > consumed?matchRange.location + matchRange.length - consumed:0;
                    startRange = NSMakeRange(start, mutableAttributedString.string.length - start);
            }
        }
    }
    return mutableAttributedString;
}
+(void) addLineSpacing:(int)space string:(NSMutableAttributedString *)attributedString;
{
unsigned int length;
NSRange effectiveRange;
id attributeValue;
length = [attributedString length];
effectiveRange = NSMakeRange(0, 0);

while (NSMaxRange(effectiveRange) < length)
{
    attributeValue = [attributedString attribute:NSParagraphStyleAttributeName
                                         atIndex:NSMaxRange(effectiveRange) effectiveRange:&effectiveRange];
    if([attributeValue isKindOfClass:[NSMutableParagraphStyle class]])
    {
        NSMutableParagraphStyle *style = (NSMutableParagraphStyle*)attributeValue;
        [style setLineSpacing:space];
        [attributedString addAttribute:NSParagraphStyleAttributeName value:style range:effectiveRange];
    }
    else if(attributeValue == nil)
    {
        NSMutableParagraphStyle *paragraphStyle = NSMutableParagraphStyle.new;
        [paragraphStyle setLineSpacing:space];
        [attributedString addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:effectiveRange];
    }
}
}
@end
