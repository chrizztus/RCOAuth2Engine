//
//  RCOAuth2Engine.m
//
//  Created by Ruiwen Chua on 5/16/12.
//  Copyright (c) 2012 Ruiwen Chua. MIT Licensed
//

#import "RCOAuth2Engine.h"

#define oAuthKeys [NSArray arrayWithObjects:@"access_token", @"expires_in", @"refresh_token", @"scope", nil]

@interface RCOAuth2Engine ()

- (void)setAuthPath:(NSString *)authPath;
- (void)setTokenPath:(NSString *)tokenPath;
- (void)removeOAuthTokenFromKeychain;
- (void)storeOAuthTokenInKeychain;
- (void)retrieveOAuthTokenFromKeychain;

@end


@implementation RCOAuth2Engine

- (NSString *)hostname {
	return (_hostname) ? _hostname : @"";
}

- (NSString *)authPath {
	return (_authPath) ? _authPath : @"";
}

- (NSString *)tokenPath {
	return (_tokenPath) ? _tokenPath : @"";
}

- (NSString *)redirect {
	return (_redirect) ? _redirect : @"";
}

- (NSString *)clientId {
	return (_tokens) ? [_tokens objectForKey:@"clientId"] : @"";
}

- (NSString *)clientSecret {
	return (_tokens) ? [_tokens objectForKey:@"clientSecret"] : @"";
}

- (void)setClientId:(NSString *)clientId {
	if (_tokens) {
		[_tokens setObject:clientId forKey:@"clientId"];
	}
}

- (void)setClientSecret:(NSString *)clientSecret {
	if(_tokens) {
		[_tokens setObject:clientSecret forKey:@"clientSecret"];
	}
}


- (void)setAuthPath:(NSString *)authPath {
	_authPath = authPath;
}

- (void)setTokenPath:(NSString *)tokenPath {
	_tokenPath = tokenPath;
}


- (RCOAuth2Engine *)initWithHostname:(NSString *)hostname customHeaderFields:(NSDictionary *)headers clientId:(NSString *)clientId clientSecret:(NSString *)clientSecret authPath:(NSString *)authPath tokenPath:(NSString *)tokenPath redirectURI:(NSString *)redirect {

	self = [super initWithHostName:hostname customHeaderFields:headers];
	
	if (self) {

		NSLog(@"Begin init setup");
		_tokens = [[NSMutableDictionary alloc] init];

		[self setClientId:clientId];
		[self setClientSecret:clientSecret];
		
		_hostname = hostname;
		_authPath = authPath;
		_tokenPath = tokenPath;
		_redirect = redirect;
		
		// Retrieve tokens from Keychain if possible
		NSLog(@"Retrieving");
		[self retrieveOAuthTokenFromKeychain];
		
		NSLog(@"Init tokens: %@", _tokens);
		
	}
	
	return self;
}

- (BOOL)isAuthenticated {
	NSLog(@"isAuthenticated");
	NSLog(@"%@", _tokens);
	return [_tokens objectForKey:@"access_token"] != nil;
}


- (void)authenticateWithCompletionBlock:(RCOAuth2CompletionBlock)completionBlock {

	// Store the Completion Block to call after authentication
	_oAuthCompletionBlock = completionBlock;
	
	// Begin OAuth2 
	NSLog(@"Begin the OAuth!");
	// Build the params
	NSMutableDictionary *p = [NSMutableDictionary dictionaryWithObjectsAndKeys:
															@"code", @"response_type", 
															self.clientId, @"client_id",
															self.redirect, @"redirect_uri",
															@"read", @"scope",
															@"write", @"scope",
																							nil];
	
	MKNetworkOperation *op = [self operationWithPath:self.authPath
											  params:p
										  httpMethod:@"GET"];
	
	[op onCompletion:^(MKNetworkOperation *completedOperation) {
		NSLog(@"Step one complete");

		NSURL *url = [NSURL URLWithString:[completedOperation url]];
		
		if(url && [[url host] isEqualToString:self.hostname]) {
			NSLog(@"%@", url);
			[[UIApplication sharedApplication] openURL:url]; // Open the URL in Safari
		}
		else {
			//NSLog(@"Headers: %@", headers);
		}
		
	} onError:^(NSError *error) {
		NSLog(@"Error");
	}];
									
	[self enqueueOperation:op];
}

- (void)completeOAuthWithCode:(NSString *)code {
	NSLog(@"completeOAuth: %@", code);

	NSMutableDictionary *p = [NSMutableDictionary dictionaryWithObjectsAndKeys:
											@"authorization_code", @"grant_type",
												self.clientSecret, @"client_secret",
													self.clientId, @"client_id",
															 code, @"code",
													self.redirect, @"redirect_uri", 
																				nil];
	
	MKNetworkOperation *op = [self operationWithPath:self.tokenPath
											  params:p
										  httpMethod:@"POST"];
	
	
	[op onCompletion:^(MKNetworkOperation *completedOperation) {
		NSLog(@"Step Two complete");
		
		// Process the data
		NSDictionary *data =[completedOperation responseJSON];
		
		for (NSString *k in oAuthKeys) {
			[_tokens setObject:[data objectForKey:k] forKey:k];
		}
		
		NSLog(@"Tokens: %@", _tokens);
		
		// Store them in the Keychain
		[self storeOAuthTokenInKeychain];
		
		// Set the headers

		// Complete the callback from earlier
		if (_oAuthCompletionBlock) {
			NSLog(@"Sending..");
			_oAuthCompletionBlock(nil);
		}
		
	} onError:^(NSError *error) {
		NSLog(@"Step Two Error");
	}];
	
	[self enqueueOperation:op];
}

- (void)parseOAuth2Query:(NSURL *)url {
	NSArray *query = [url.query componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"&="]];
	
	NSLog(@"Query: %@", query);
	
	// Extract the code from the return URL
	NSString *code = [query objectAtIndex:[query indexOfObject:@"code"]+1];	
	NSLog(@"Code: %@", code);
	
	[self completeOAuthWithCode:code];
}
	 

- (void)resetAuth {
	// Clear the items in memory
	for(NSString *k in oAuthKeys) {
		[_tokens removeObjectForKey:k];
	}
	
	// Clear the Keychain
	[self removeOAuthTokenFromKeychain];
}

- (void)prepareHeaders:(MKNetworkOperation *)operation {
	[super prepareHeaders:operation];
	
	// Add more headers
	// Authorization: OAuth2 access_token=adfadfad
	if([_tokens objectForKey:@"access_token"]) { 
		NSString *authHeader = [NSString stringWithFormat:@"access_token=%@", [_tokens objectForKey:@"access_token"]];
		[operation setAuthorizationHeaderValue:authHeader forAuthType:@"OAuth2"];
	}

}
	 
#pragma mark - OAuth Access Token store/retrieve, borrowed from https://github.com/rsieiro/RSOAuthEngine

- (void)removeOAuthTokenFromKeychain
{
    // Build the keychain query
    NSMutableDictionary *keychainQuery = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          (__bridge_transfer NSString *)kSecClassGenericPassword, (__bridge_transfer NSString *)kSecClass,
                                          [self clientId], kSecAttrService,
                                          [self clientId], kSecAttrAccount,
                                          kCFBooleanTrue, kSecReturnAttributes,
                                          nil];
    
    // If there's a token stored for this user, delete it
    CFDictionaryRef query = (__bridge_retained CFDictionaryRef) keychainQuery;
    SecItemDelete(query);
    CFRelease(query);
}

- (void)storeOAuthTokenInKeychain
{
    // Build the keychain query
    NSMutableDictionary *keychainQuery = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          (__bridge_transfer NSString *)kSecClassGenericPassword, (__bridge_transfer NSString *)kSecClass,
                                          [self clientId], kSecAttrService,
                                          [self clientId], kSecAttrAccount,
                                          kCFBooleanTrue, kSecReturnAttributes,
                                          nil];
    
    CFTypeRef resData = NULL;
    
    // If there's a token stored for this user, delete it first
    CFDictionaryRef query = (__bridge_retained CFDictionaryRef) keychainQuery;
    SecItemDelete(query);
    CFRelease(query);
    
    // Build the token dictionary
    /*NSMutableDictionary *tokenDictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                            self.token, @"oauth_token",
                                            self.tokenSecret, @"oauth_token_secret",
                                            //self.screenName, @"screen_name",
                                            nil];
    */
	
    // Add the token dictionary to the query
    [keychainQuery setObject:[NSKeyedArchiver archivedDataWithRootObject:_tokens] 
                      forKey:(__bridge_transfer NSString *)kSecValueData];
    
    // Add the token data to the keychain
    // Even if we never use resData, replacing with NULL in the call throws EXC_BAD_ACCESS
    query = (__bridge_retained CFDictionaryRef) keychainQuery;
    SecItemAdd(query, (CFTypeRef *) &resData);
    CFRelease(query);
}

- (void)retrieveOAuthTokenFromKeychain
{
    // Build the keychain query
    NSMutableDictionary *keychainQuery = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          (__bridge_transfer NSString *)kSecClassGenericPassword, (__bridge_transfer NSString *)kSecClass,
                                          [self clientId], kSecAttrService,
                                          [self clientId], kSecAttrAccount,
                                          kCFBooleanTrue, kSecReturnData,
                                          kSecMatchLimitOne, kSecMatchLimit,
                                          nil];
    
    // Get the token data from the keychain
    CFTypeRef resData = NULL;
    
    // Get the token dictionary from the keychain
    CFDictionaryRef query = (__bridge_retained CFDictionaryRef) keychainQuery;
    
    if (SecItemCopyMatching(query, (CFTypeRef *) &resData) == noErr)
    {
        NSData *resultData = (__bridge_transfer NSData *)resData;
        
        if (resultData)
        {
            NSMutableDictionary *tokenDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:resultData];
            
            if (tokenDictionary) {
				_tokens = tokenDictionary;
            }
        }
    }
    
    CFRelease(query);
}

@end
