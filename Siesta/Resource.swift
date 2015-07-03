//
//  Resource.swift
//  Siesta
//
//  Created by Paul on 2015/6/16.
//  Copyright © 2015 Bust Out Solutions. All rights reserved.
//

import Alamofire

public class Resource
    {
    // MARK: Configuration
    
    public let service: Service
    public let url: NSURL? // TODO: figure out what to do about invalid URLs
    
    // MARK: Request management
    
    public var loading: Bool { return !loadRequests.isEmpty }
    public private(set) var loadRequests = Set<Request>()  // TOOD: How to handle concurrent POST & GET?
    
    // MARK: Resource state

    public private(set) var latestData: Data?
    public private(set) var latestError: Error?
    public var data: AnyObject? { return latestData?.payload }
    public var timestamp: NSTimeInterval
        {
        return max(
            latestData?.timestamp ?? 0,
            latestError?.timestamp ?? 0)
        }
    
    // MARK: Observers

    private var observers = [ObserverEntry]()
    
    // MARK: -
    
    init(service: Service, url: NSURL?)
        {
        self.service = service
        self.url = url?.absoluteURL
        NSNotificationCenter.defaultCenter().addObserverForName(
                UIApplicationDidReceiveMemoryWarningNotification,
                object: nil,
                queue: nil)
            {
            [weak self] _ in
            self?.cleanDefunctObservers()
            }
        }
    
    // MARK: URL Navigation
    
    public func child(path: String) -> Resource
        {
        return service.resource(url?.URLByAppendingPathComponent(path))
        }
    
    public func relative(path: String) -> Resource
        {
        return service.resource(NSURL(string: path, relativeToURL: url))
        }
    
    // MARK: Requests
    
    public func request(
            method:          Alamofire.Method,
            requestMutation: NSMutableURLRequest -> () = { _ in })
        -> Request
        {
        let nsreq = NSMutableURLRequest(URL: url!)
        nsreq.HTTPMethod = method.rawValue
        requestMutation(nsreq)

        return service.sessionManager.request(nsreq)
        }
    
    public func load() -> Request
        {
        let req = request(.GET)
            {
            nsreq in
            if let etag = self.latestData?.etag
                { nsreq.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            }
        
        loadRequests.insert(req)
        req.response
            {
            [weak self, weak req] _ in
            if let req = req
                { self?.loadRequests.remove(req) }
            }
        
        req.resourceResponse(self,
            success:     self.updateStateWithData,
            notModified: self.updateStateWithDataNotModified,
            error:       self.updateStateWithError)

        self.notifyObservers(.REQUESTED)

        return req
        }
    
    private func updateStateWithData(data: Data)
        {
        self.latestError = nil
        self.latestData = data
        
        notifyObservers(.NEW_DATA_RESPONSE)
        }

    private func updateStateWithDataNotModified()
        {
        self.latestError = nil
        self.latestData?.touch()
        
        notifyObservers(.NOT_MODIFIED_RESPONSE)
        }
    
    private func updateStateWithError(error: Error)
        {
        if let nserror = error.nsError
            where nserror.domain == "NSURLErrorDomain"
               && nserror.code == NSURLErrorCancelled
            {
            notifyObservers(.REQUEST_CANCELLED)
            return
            }
        
        self.latestError = error

        notifyObservers(.ERROR_RESPONSE)
        }

    // MARK: Observers
    
    /**
        Adds an observer without retaining a reference to it.
    */
    public func addObserver(observerAndOwner: protocol<ResourceObserver, AnyObject>)
        {
        addObserverEntry(
            DirectObserverEntry(resource: self, observerAndOwner: observerAndOwner))
        }
    
    public func addObserver(observer: ResourceObserver, owner: AnyObject)
        {
        addObserverEntry(
            OwnedObjectObserverEntry(resource: self, observer: observer, owner: owner))
        }
    
    public func addObserver(owner: AnyObject, closure: ResourceObserverClosure)
        {
        addObserver(ClosureObserver(closure: closure), owner: owner)
        }
    
    private func addObserverEntry(entry: ObserverEntry)
        {
        observers.append(entry)
        entry.observer?.resourceChanged(self, event: .OBSERVER_ADDED)
        }
    
    public func removeObservers(ownedBy owner: AnyObject)
        {
        observers = observers.filter
            { $0.owner !== owner }
        }
    
    private func notifyObservers(event: ResourceEvent)
        {
        cleanDefunctObservers()
        
        for entry in observers
            { entry.observer?.resourceChanged(self, event: event) }
        }
    
    func cleanDefunctObservers()
        {
        observers = observers.filter
            { $0.owner !== nil }
        }
    }



private protocol ObserverEntry
    {
    var observer: ResourceObserver? { get }
    var owner: AnyObject? { get }
    }

private struct DirectObserverEntry: ObserverEntry
    {
    // Intentional reference cycle to keep Resource alive as long
    // as it has observers.
    let resource: Resource
    
    weak var observerAndOwner: protocol<ResourceObserver,AnyObject>?
    var observer: ResourceObserver? { return observerAndOwner }
    var owner:    AnyObject?        { return observerAndOwner }
    }

private struct OwnedObjectObserverEntry: ObserverEntry
    {
    // Intentional reference cycle to keep Resource alive as long
    // as it has observers.
    let resource: Resource
    
    let observer: ResourceObserver?
    weak var owner: AnyObject?
    }

private struct ClosureObserver: ResourceObserver
    {
    private let closure: ResourceObserverClosure
    
    func resourceChanged(resource: Resource, event: ResourceEvent)
        {
        closure(resource: resource, event: event)
        }
    }
