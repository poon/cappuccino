/*
 * CPKeyedArchiver.j
 * Foundation
 *
 * Created by Francisco Tolmasky.
 * Copyright 2008, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

import "CPData.j"
import "CPCoder.j"
import "CPArray.j"
import "CPString.j"
import "CPNumber.j"
import "CPDictionary.j"
import "CPValue.j"

var CPArchiverReplacementClassNames                     = nil;

var _CPKeyedArchiverDidEncodeObjectSelector             = 1,
    _CPKeyedArchiverWillEncodeObjectSelector            = 2,
    _CPKeyedArchiverWillReplaceObjectWithObjectSelector = 4,
    _CPKeyedArchiverDidFinishSelector                   = 8,
    _CPKeyedArchiverWillFinishSelector                  = 16;
    
var _CPKeyedArchiverNullString                          = "$null",
    _CPKeyedArchiverNullReference                       = nil,
    
    _CPKeyedArchiverUIDKey                              = "CP$UID",
    
    _CPKeyedArchiverTopKey                              = "$top",
    _CPKeyedArchiverObjectsKey                          = "$objects",
    _CPKeyedArchiverArchiverKey                         = "$archiver",
    _CPKeyedArchiverVersionKey                          = "$version",
    
    _CPKeyedArchiverClassNameKey                        = "$classname",
    _CPKeyedArchiverClassesKey                          = "$classes",
    _CPKeyedArchiverClassKey                            = "$class";                     

var _CPKeyedArchiverStringClass                         = Nil,
    _CPKeyedArchiverNumberClass                         = Nil;

/* @ignore */
@implementation _CPKeyedArchiverValue : CPValue
{
}
@end

/*
    Implements keyed archiving of object graphs. Archiving means to
    write data out in a format that be read in again later, or possibly
    stored in a file. To read the data back in, use a
    <code>CPKeyedUnarchiver</code>.

    @delegate -(void)archiverWillFinish:(CPKeyedArchiver)archiver;
    Called when the encoding is about to finish.
    @param archiver the archiver that's about to finish

    @delegate -(void)archiver:(CPKeyedArchiver)archiver didEncodeObject:(id)object;
    Called when an object is encoded into the archiver.
    @param archiver the archiver that encoded the object
    @param object the object that was encoded

    @delegate -(void)archiverDidFinish:(CPKeyedArchiver)archiver;
    Called when the archiver finishes encoding.
    @param archiver the arhiver that finished encoding

    @delegate -(id)archiver:(CPKeyedArchiver)archiver willEncodeObject:(id)object;
    Called when an object is about to be encoded. Allows the delegate to replace
    the object that gets encoded with a substitute or <code>nil</code>.
    @param archiver the archiver encoding the object
    @param object the candidate object for encoding
    @return the object to encode

    @delegate -(void)archiver:(CPKeyedArchiver)archiver willReplaceObject:(id)object withObject:(id)newObject;
    Called when an object is being replaced in the archiver.
    @param archiver the archiver encoding the object
    @param object the object to be replaced
    @param newObject the replacement object
*/
@implementation CPKeyedArchiver : CPCoder
{
    id                      _delegate;
    unsigned                _delegateSelectors;
    
    CPData                  _data;
    
    CPArray                 _objects;

    CPDictionary            _UIDs;
    CPDictionary            _conditionalUIDs;
    
    CPDictionary            _replacementObjects;
    CPDictionary            _replacementClassNames;
    
    id                      _plistObject;
    CPMutableArray          _plistObjects;
    
    CPPropertyListFormat    _outputFormat;
    
}

/*
    @ignore
*/
+ (void)initialize
{
    if (self != [CPKeyedArchiver class])
        return;
    
    _CPKeyedArchiverStringClass = [CPString class];
    _CPKeyedArchiverNumberClass = [CPNumber class];
    
    _CPKeyedArchiverNullReference = [CPDictionary dictionaryWithObject:0 forKey:_CPKeyedArchiverUIDKey];
}

+ (BOOL)allowsKeyedCoding
{
    return YES;
}

/*
    Archives the specified object.
    @param anObject the object to archive
    @return the archived object
*/
+ (CPData)archivedDataWithRootObject:(id)anObject
{
    var data = [CPData dataWithPlistObject:nil],
        archiver = [[self alloc] initForWritingWithMutableData:data];
    
    [archiver encodeObject:anObject forKey:@"root"];
    [archiver finishEncoding];

    return data;
}

// Initializing an NSKeyedArchiver object
/*
    Initializes the keyed archiver with the specified <code>CPMutableData</code> for writing.
    @param data the object to archive to
    @return the initialized keyed archiver
*/
- (id)initForWritingWithMutableData:(CPMutableData)data
{
    self = [super init];
    
    if (self)
    {
        _data = data;
        
        _objects = [];
        
        _UIDs = [CPDictionary dictionary];
        _conditionalUIDs = [CPDictionary dictionary];
        
        _replacementObjects = [CPDictionary dictionary];
        
        _data = data;
        
        _plistObject = [CPDictionary dictionary];
        _plistObjects = [CPArray arrayWithObject:_CPKeyedArchiverNullString];
    }
    
    return self;
}

// Archiving Data
/*
    Finishes up writing any left over data, and notifies delegates.
    After calling this method, the archiver can not encode anymore objects.
*/
- (void)finishEncoding
{
    if (_delegate && _delegateSelectors & _CPKeyedArchiverWillFinishSelector)
        [_delegate archiverWillFinish:self];
    
    var i = 0,
        topObject = _plistObject,
        classes = [];
    
    for (; i < _objects.length; ++i)
    {
        var object = _objects[i],
            theClass = [object classForKeyedArchiver];
        
        // Do whatever with the class, yo.
        // We call willEncodeObject previously.
        
        _plistObject = _plistObjects[[_UIDs objectForKey:[object hash]]];
        [object encodeWithCoder:self];        
        
        if (_delegate && _delegateSelectors & _CPKeyedArchiverDidEncodeObjectSelector)
            [_delegate archiver:self didEncodeObject:object];
    }
    
    _plistObject = [CPDictionary dictionary];
    
    [_plistObject setObject:topObject forKey:_CPKeyedArchiverTopKey];
    [_plistObject setObject:_plistObjects forKey:_CPKeyedArchiverObjectsKey];
    [_plistObject setObject:[self className] forKey:_CPKeyedArchiverArchiverKey];
    [_plistObject setObject:@"100000" forKey:_CPKeyedArchiverVersionKey];
    
    [_data setPlistObject:_plistObject];

    if (_delegate && _delegateSelectors & _CPKeyedArchiverDidFinishSelector)
        [_delegate archiverDidFinish:self];
}

/*
    Returns the property list format used to archive objects.
*/
- (CPPropertyListFormat)outputFormat
{
    return _outputFormat;
}

/*
    Sets the property list format the archiver should use to archive objects.
    @param aPropertyListFormat the format to use
*/
- (void)setOutputFormat:(CPPropertyListFormat)aPropertyListFormat
{
    _outputFormat = aPropertyListFormat;
}

/*
    Encodes a <code>BOOL</code> value
    @param aBool the <code>BOOL</code> value
    @param aKey the key to associate with the <code>BOOL</code>
*/
- (void)encodeBool:(BOOL)aBOOL forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, aBOOL, NO) forKey:aKey];
}

/*
    Encodes a <code>double</code> value
    @param aDouble the <code>double</code> value
    @param aKey the key to associate with the <code>double</code>
*/
- (void)encodeDouble:(double)aDouble forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, aDouble, NO) forKey:aKey];
}

/*
    Encodes a <code>float</code> value
    @param aFloat the <code>float</code> value
    @param aKey the key to associate with the <code>float</code>
*/
- (void)encodeFloat:(float)aFloat forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, aFloat, NO) forKey:aKey];
}

/*
    Encodes a <code>int</code> value
    @param anInt the <code>int</code> value
    @param aKey the key to associate with the <code>int</code>
*/
- (void)encodeInt:(float)anInt forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, anInt, NO) forKey:aKey];
}

// Managing Delegates
/*
    Sets the keyed archiver's delegate
*/
- (void)setDelegate:(id)aDelegate
{
    _delegate = aDelegate;
    
    if ([_delegate respondsToSelector:@selector(archiver:didEncodeObject:)])
        _delegateSelectors |= _CPKeyedArchiverDidEncodeObjectSelector;
        
    if ([_delegate respondsToSelector:@selector(archiver:willEncodeObject:)])
        _delegateSelectors |= _CPKeyedArchiverWillEncodeObjectSelector;
    
    if ([_delegate respondsToSelector:@selector(archiver:willReplaceObject:withObject:)])
        _delegateSelectors |= _CPKeyedArchiverWillReplaceObjectWithObjectSelector;

    if ([_delegate respondsToSelector:@selector(archiver:didFinishEncoding:)])
        _delegateSelectors |= _CPKeyedArchiverDidFinishEncodingSelector;
        
    if ([_delegate respondsToSelector:@selector(archiver:willFinishEncoding:)])
        _delegateSelectors |= _CPKeyedArchiverWillFinishEncodingSelector;
    
}

/*
    Returns the keyed archiver's delegate
*/
- (id)delegate
{
    return _delegate;
}

/*
    Encodes a <objj>CGPoint</objj>
    @param aPoint the point to encode
    @param aKey the key to associate with the point
*/
- (void)encodePoint:(CGPoint)aPoint forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, CPStringFromPoint(aPoint), NO) forKey:aKey];
}

/*
    Encodes a <objj>CGRect</objj>
    @param aRect the rectangle to encode
    @param aKey the key to associate with the rectangle
*/
- (void)encodeRect:(CGRect)aRect forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, CPStringFromRect(aRect), NO) forKey:aKey];
}

/*
    Encodes a <objj>CGSize</objj>
    @param aSize the size to encode
    @param aKey the key to associate with the size
*/
- (void)encodeSize:(CGSize)aSize forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, CPStringFromSize(aSize), NO) forKey:aKey];
}

/*
    Encodes an conditionally. The method checks if the object has already been
    coded into this data stream before. If so, it will only encode a reference
    to that first object to save memory.
    @param anObject the object to to conditionally encode
    @param aKey the key to associate with the object
*/
- (void)encodeConditionalObject:(id)anObject forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, anObject, YES) forKey:aKey];
}

/*
    Encodes a number
    @param aNumber the number to encode
    @param aKey the key to associate with the object
*/
- (void)encodeNumber:(CPNumber)aNumber forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, aNuumber, NO) forKey:aKey];
}

/*
    Encdoes an object
    @param anObject the object to encode
    @param aKey the key to associate with the object
*/
- (void)encodeObject:(id)anObject forKey:(CPString)aKey
{
    [_plistObject setObject:_CPKeyedArchiverEncodeObject(self, anObject, NO) forKey:aKey]; 
}

/* @ignore */
- (void)_encodeArrayOfObjects:(CPArray)objects forKey:(CPString)aKey
{
    var i = 0,
        count = objects.length,
        references = [CPArray arrayWithCapacity:count];
        
    for (; i < count; ++i)
        [references addObject:_CPKeyedArchiverEncodeObject(self, objects[i], NO)];
        
    [_plistObject setObject:references forKey:aKey];
}

/* @ignore */
- (void)_encodeDictionaryOfObjects:(CPDictionary)aDictionary forKey:(CPString)aKey
{
    var key,
        keys = [aDictionary keyEnumerator],
        references = [CPDictionary dictionary];
    
    while (key = [keys nextObject])
        [references setObject:_CPKeyedArchiverEncodeObject(self, [aDictionary objectForKey:key], NO) forKey:key];
    
    [_plistObject setObject:references forKey:aKey];
}

// Managing classes and class names
/*
    Allows substitution of class types for encoding. Specifically classes
    of type <code>aClass</code> encountered by all keyed archivers will
    instead be archived as a class of type <code>aClassName</code>.
    @param aClassName the substitute class name
    @param aClass the class to substitute
*/
+ (void)setClassName:(CPString)aClassName forClass:(Class)aClass
{
    if (!CPArchiverReplacementClassNames)
        CPArchiverReplacementClassNames = [CPDictionary dictionary];
    
    [CPArchiverReplacementClassNames setObject:aClassName forKey:CPStringFromClass(aClass)];
}

/*
    Returns the name of the substitute class used for encoding
    <code>aClass</code> by all keyed archivers.
    @param aClass the class to substitute
    @return the name of the substitute class, or <code>nil</code> if there
    is no substitute class
*/
+ (CPString)classNameForClass:(Class)aClass
{
    if (!CPArchiverReplacementClassNames)
        return aClass.name;

    var className = [CPArchiverReplacementClassNames objectForKey:CPStringFromClass(aClassName)];
    
    return className ? className : aClass.name;
}

/*
    Allows substitution of class types for encoding. Specifically classes
    of type <code>aClass</code> encountered by this keyed archiver will
    instead be archived as a class of type <code>aClassName</code>.
    @param aClassName the substitute class name
    @param aClass the class to substitute
*/
- (void)setClassName:(CPString)aClassName forClass:(Class)aClass
{
    if (!_replacementClassNames)
        _replacementClassNames = [CPDictionary dictionary];
    
    [_replacementClassNames setObject:aClassName forKey:CPStringFromClass(aClass)];
}

/*
    Returns the name of the substitute class used for encoding <code>aClass</code> by this keyed archiver.
    @param aClass the class to substitute
    @return the name of the substitute class, or <code>nil</code> if there is no substitute class
*/
- (CPString)classNameForClass:(Class)aClass
{
    if (!_replacementClassNames)
        return aClass.name;

    var className = [_replacementClassNames objectForKey:CPStringFromClass(aClassName)];
    
    return className ? className : aClass.name;
}

@end

var _CPKeyedArchiverEncodeObject = function(self, anObject, isConditional)
{
    // We wrap primitive JavaScript objects in a unique subclass of CPValue.
    // This way, when we unarchive, we know to unwrap it, since 
    // _CPKeyedArchiverValue should not be used anywhere else.
    if (anObject != nil && !anObject.isa)
        anObject = [_CPKeyedArchiverValue valueWithJSObject:anObject];
    
    // Get the proper replacement object
    var hash = [anObject hash],
        object = [self._replacementObjects objectForKey:hash];

    // If a replacement object doesn't exist, then actually ask for one.
    // Explicitly compare to nil because object could be === 0.
    if (object == nil)
    {
        object = [anObject replacementObjectForKeyedArchiver:self];
        
        // Notify our delegate of this replacement.
        if (self._delegate)
        {
            if (object != anObject && self._delegateSelectors & _CPKeyedArchiverWillReplaceObjectWithObjectSelector)
                [self._delegate archiver:self willReplaceObject:anObject withObject:object];
            
            if (self._delegateSelectors & _CPKeyedArchiverWillEncodeObjectSelector)
            {
                anObject = [self._delegate archiver:self willEncodeObject:object];
                
                if (anObject != object && self._delegateSelectors & _CPKeyedArchiverWillReplaceObjectWithObjectSelector)
                    [self._delegate archiver:self willReplaceObject:object withObject:anObject];
                    
                object = anObject;
            }
        }
        
        [self._replacementObjects setObject:object forKey:hash];
    }
    
    // If we still don't have an object by this point, then return a 
    // reference to the null object.
    // Explicitly compare to nil because object could be === 0.
    if (object == nil)
        return _CPKeyedArchiverNullReference;
    
    // If not, then grab the object's UID
    var UID = [self._UIDs objectForKey:hash = [object hash]];
    
    // If this object doesn't have a unique index in the object table yet, 
    // then it also hasn't been properly encoded.  We explicitly compare 
    // index to nil since it could be 0, which would also evaluate to false.
    if (UID == nil)
    {
        // If it is being conditionally encoded, then 
        if (isConditional)
        {
            // If we haven't already noted this conditional object...
            if ((UID = [self._conditionalUIDs objectForKey:hash]) == nil)
            {
                // Use the null object as a placeholder.
                [self._conditionalUIDs setObject:UID = [self._plistObjects count] forKey:hash];
                [self._plistObjects addObject:_CPKeyedArchiverNullString];
            }
        }
        else
        {
            var theClass = [anObject classForKeyedArchiver],
                plistObject = nil,
                shouldEncodeObject = NO;
            
            if (theClass == _CPKeyedArchiverStringClass || theClass == _CPKeyedArchiverNumberClass)// || theClass == _CPKeyedArchiverBooleanClass)
                plistObject = object;
            else
            {
                shouldEncodeObject = YES;
                plistObject = [CPDictionary dictionary];
            }
            
            // If this object was previously encoded conditionally...
            if ((UID = [self._conditionalUIDs objectForKey:hash]) == nil)
            {
                [self._UIDs setObject:UID = [self._plistObjects count] forKey:hash];
                [self._plistObjects addObject:plistObject];
                
                // Only encode the object if it is not the same as the plist object.
                if (shouldEncodeObject)
                {
                    [self._objects addObject:object];
                    
                    var className = [self classNameForClass:theClass];
        
                    if (!className)
                        className = [[self class] classNameForClass:theClass];
                    
                    if (!className)
                        className = theClass.name;
                    else
                        theClass = window[className];

                    var classUID = [self._UIDs objectForKey:className];
                    
                    if (!classUID)
                    {
                        var plistClass = [CPDictionary dictionary],
                            hierarchy = [];
                        
                        [plistClass setObject:className forKey:_CPKeyedArchiverClassNameKey];
                        
                        do
                        {
                            [hierarchy addObject:CPStringFromClass(theClass)];
                        } while (theClass = [theClass superclass]);
                        
                        [plistClass setObject:hierarchy forKey:_CPKeyedArchiverClassesKey];
                        
                        classUID = [self._plistObjects count];
                        [self._plistObjects addObject:plistClass];
                        [self._UIDs setObject:classUID forKey:className];
                    }

                    [plistObject setObject:[CPDictionary dictionaryWithObject:classUID forKey:_CPKeyedArchiverUIDKey] forKey:_CPKeyedArchiverClassKey];
                }
            }
            else
            {
                [self._UIDs setObject:object forKey:UID];
                [self._plistObjects replaceObjectAtIndex:UID withObject:plistObject];
            }
        }
    }

    return [CPDictionary dictionaryWithObject:UID forKey:_CPKeyedArchiverUIDKey];
}