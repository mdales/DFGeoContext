//
//  DFGeoContext.m
//
//  Created by Michael Dales on 13/03/2010.
//  Copyright 2010 Michael Dales. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of its contributors may be used
//   to endorse or promote products derived from this software without specific
//   prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// 


#import "DFGeoContext.h"

#import <AddressBook/AddressBook.h>
#import "JSON.h"
#import "ASI/ASIFormDataRequest.h"

#define CLOUDMADE_KEY @"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"


NSString* const kDFGeoContextHome = @"_$!<Home>!$_"; //kABHomeLabel;
NSString* const kDFGeoContextWork = @"_$!<Work>!$_"; //kABWorkLabel;
NSString* const kDFGeoContextOtherWhere = @"Otherwhere";
NSString* const kDFGeoContextUnknow = @"Unknown";

@implementation DFGeoContext

@synthesize delegate;

///////////////////////////////////////////////////////////////////////////////
//
//
- (id)init
{
	if ((self = [super init]) != nil)
	{
		lastLocation = nil;
		
		ABAddressBook *addressBook = [ABAddressBook addressBook];
		ABPerson *me = [addressBook me];
		ABMultiValue *address_list = [me valueForProperty: kABAddressProperty];
		
		
		contextList = [[NSMutableArray alloc] initWithCapacity: [address_list count]];
		
		for (int i = 0; i < [address_list count]; i++)
		{
			NSMutableDictionary *contextInfo = [[NSMutableDictionary alloc] init];
			
			NSString *label = [address_list labelAtIndex: i];
			[contextInfo setObject: label
							forKey: @"label"];
			
			NSDictionary *address_info = [address_list valueAtIndex: i];
			[contextInfo setObject: address_info
							forKey: @"address_info"];
			
			NSString *locationName = [NSString stringWithFormat: @"%@, %@, %@",
									  [address_info valueForKey: @"Street"],
									  [address_info valueForKey: @"City"],
									  [address_info valueForKey: @"Country"]];
			[contextInfo setObject: locationName
							forKey: @"location_name"];
			[contextList addObject: contextInfo];
			
			// try and find the location for each context
			
			NSURL *url = [NSURL URLWithString: [NSString stringWithFormat: @"http://geocoding.cloudmade.com/%@/geocoding/v2/find.js", CLOUDMADE_KEY]];
			
			ASIFormDataRequest *request = [[ASIFormDataRequest alloc] initWithURL: url];
			[contextInfo setObject: request
							forKey: @"cloudmade_request"];
			request.userInfo = contextInfo;
			
			
			[request setPostValue: locationName
						   forKey: @"query"];
			
			[request setDelegate: self];
			[request startAsynchronous];
		}
		
	}
	
	return self;
}


///////////////////////////////////////////////////////////////////////////////
//
//
- (void)dealloc
{
	[contextList release];
	[super dealloc];
}


///////////////////////////////////////////////////////////////////////////////
//
//
- (void)requestFinished:(ASIHTTPRequest *)request
{
	NSMutableDictionary *contextInfo = (NSMutableDictionary*)[request userInfo];
	
	NSString *responseString = [request responseString];
	NSDictionary *reply = [responseString JSONValue];
		  
	NSArray *features = [reply valueForKey: @"features"];
	
	// lazy, just take the first feature
	NSDictionary *firstFeature = [features objectAtIndex: 0];
	
	NSDictionary *centroid = [firstFeature valueForKey: @"centroid"];
	NSArray *coordinates = [centroid valueForKey: @"coordinates"];
	
	// we have coordinates, so create a CLLocation object from all this
	CLLocation* location = [[CLLocation alloc] initWithLatitude: [[coordinates objectAtIndex: 0] floatValue]
														  longitude: [[coordinates objectAtIndex: 1] floatValue]];
	
	[contextInfo setObject: location
					forKey: @"location"];
	[contextInfo removeObjectForKey: @"cloudmade_request"];
	
	// if we're slow getting data from cloudmade, then we might already 
	// have had the location
	if (lastLocation != nil)
	{
		if ([lastLocation distanceFromLocation: location] < 100.0)
		{
			[delegate userContext: self
						updatedTo: [contextInfo objectForKey: @"label"]];
		}
	}
}


///////////////////////////////////////////////////////////////////////////////
//
//
- (void)requestFailed:(ASIHTTPRequest *)request
{
	NSError *error = [request error];
	NSLog(@"error from cloudmade: %@", [error localizedDescription]);
	
	// clean up this request
	NSMutableDictionary *contextInfo = (NSMutableDictionary*)[request userInfo];
	[request release];
	
	[contextInfo removeObjectForKey: @"cloudmade_request"];
}


///////////////////////////////////////////////////////////////////////////////
//
//
- (void)startFindUserContext
{
	locationManager = [[CLLocationManager alloc] init];
	locationManager.delegate = self;
	[locationManager startUpdatingLocation];
}


///////////////////////////////////////////////////////////////////////////////
//
//
- (void)locationManager: (CLLocationManager *)manager
	didUpdateToLocation: (CLLocation *)newLocation 
		   fromLocation: (CLLocation *)oldLocation
{
	lastLocation = newLocation;
	
	NSLog(@"location update %f, %f", newLocation.coordinate.latitude, 
		  newLocation.coordinate.longitude);	

	
	[locationManager stopUpdatingLocation];

	// we know where we are, so loop through our contexts and see if we're 
	// near there
	for (NSDictionary *context in contextList)
	{
		CLLocation *location = [context objectForKey: @"location"];
		if (location != nil)
		{
			NSLog(@"distance is %g", [lastLocation distanceFromLocation: location]);
			if ([lastLocation distanceFromLocation: location] < 100.0)
			{
				NSLog(@"you found the user!");
				[delegate userContext: self
							updatedTo: [context objectForKey: @"label"]];
				return;
			}
		}
	}
	
	// if we got here, we've no idea where the user is
	[delegate userContext: self
				updatedTo: @"Otherwhere"];
}



///////////////////////////////////////////////////////////////////////////////
//
//
- (void)locationManager:(CLLocationManager *)manager 
	   didFailWithError:(NSError *)error
{
	NSLog(@"location error: %@", [error localizedDescription]);
	[locationManager stopUpdatingLocation];
	
	[delegate userContext: self
				updatedTo: @"Unknown"];
}

@end
