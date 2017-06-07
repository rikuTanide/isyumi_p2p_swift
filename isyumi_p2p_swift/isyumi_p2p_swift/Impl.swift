import Foundation
import FirebaseDatabase
import RxSwift

// Answerer
class LocalItemListUpperImpl:LocalItemListUpper {
    
    func listup() ->[ItemFile] {
        let file_manager = FileManager()
        let item_dir = file_manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("items")
        
        if !file_manager.fileExists(atPath: NSHomeDirectory() + "/Library/items"){
            return []
        }
        
        let dir_list = try! file_manager.contentsOfDirectory(at: item_dir, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants)
        var files:[ItemFile] = []
        for group_dir in dir_list {
            let group_files = try! file_manager.contentsOfDirectory(at: group_dir, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants)
            for file in group_files {
                files += [ItemFile(group_id:group_dir.pathComponents.last!,item_id:file.pathComponents.last!)]
            }
        }
        return files
        
    }
}

class DeviceIDRegistryImpl:DeviceIDRegistry {
    func read() -> String {
        
        
        let file_manager = FileManager()
        let device_id_file_path = file_manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("device_id")
        if file_manager.fileExists(atPath: NSHomeDirectory() + "/Library/device_id") {
            return try! NSString(contentsOf: device_id_file_path, encoding: String.Encoding.utf8.rawValue) as String
        }
        
        let random = RandomStringImpl()
        let device_id = random.generate(16)
        
        
        try! device_id.write(to: device_id_file_path, atomically: true, encoding: .utf8)
        
        return device_id
    }
}

class RandomStringImpl:RandomString {
    func generate(_ length: Int) -> String {
        let alphabet = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let upperBound = UInt32(alphabet.characters.count)
        
        return String((0..<length).map { _ -> Character in
            return alphabet[alphabet.index(alphabet.startIndex, offsetBy: Int(arc4random_uniform(upperBound)))]
        })
    }
}


class CurrentGroupRegistoryImpl:CurrentGroupRegistry {
    func save(_ group_id: String) {
        let file_manager = FileManager()
        let group_id_file_path = file_manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("group_id")
        try! group_id.write(to: group_id_file_path, atomically: true, encoding: .utf8)
    }
    func read() -> String? {
        let file_manager = FileManager()
        let group_id_file_path = file_manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("group_id")
        if file_manager.fileExists(atPath: NSHomeDirectory() + "/Library/group_id") {
            return try! NSString(contentsOf: group_id_file_path, encoding: String.Encoding.utf8.rawValue) as String
        }
        return nil
    }
}


class WriterImpl {
    
    init(direction:Direction) {
        let _ = direction.write.subscribe(onNext: {self.write($0.group_id,$0.item_id)})
    }
    
    func write(_ group_id: String, _ file_name: String) {
        let file_manager = FileManager()
        let item_dir = file_manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("items")
        try? file_manager.createDirectory(at: item_dir, withIntermediateDirectories: true, attributes: nil)
        let group_dir = item_dir.appendingPathComponent(group_id)
        try? file_manager.createDirectory(at: group_dir, withIntermediateDirectories: true, attributes: nil)
        let file_path = group_dir.appendingPathComponent(file_name)
        
        let tmp_file = file_manager.temporaryDirectory.appendingPathComponent(file_name)
        
        try? file_manager.moveItem(at: tmp_file, to: file_path)
    }
    
    
}



class P2PImpl {
    
    var peer:SKWPeer?

    var controller:Controller
    
    init(_ direction:Direction ,_ controller:Controller) {
        let _ = direction.item_send.subscribe(onNext: {self.send($0)})
        self.controller = controller
    }
    
    func send(_ item_send:ItemSend) {
        let label = item_send.group_id + "/" + item_send.take_device_id + "/" + item_send.give_device_id + "/" + item_send.item_id
        
        let options = SKWConnectOption()
        options.serialization = .SERIALIZATION_BINARY
        options.metadata = label
        options.reliable = true
        
        
        let remote_peer = peer?.connect(withId: item_send.take_peer_id,options:options)
        
        remote_peer?.on(.DATACONNECTION_EVENT_DATA ,callback: {obj in
            
            let file_manager = FileManager()
            let item_dir = file_manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("item")
            try? file_manager.createDirectory(at: item_dir, withIntermediateDirectories: true, attributes: nil)
            let group_dir = item_dir.appendingPathComponent(item_send.group_id)
            try? file_manager.createDirectory(at: group_dir, withIntermediateDirectories: true, attributes: nil)
            let group_file = group_dir.appendingPathComponent(item_id)
            
            
            remote_peer?.send(NSData(contentsOf:item_file))
            
        })
        
        
    }
    func streamReceive(_ controller: Controller) {
        self.controller = controller
    }
    func connect() -> Observable<String> {
        
        //Callback用
        let callback = PublishSubject<String>()
      
        let option = SKWPeerOption()
        option.debug  = .DEBUG_LEVEL_ALL_LOGS
        option.domain = "localhost"
        option.key = "**** SkyWayのID ****"
        option.type = .PEER_TYPE_SKYWAY
        option.turn = false
        option.secure = true
        self.peer = SKWPeer(options: option)
        self.peer!.on(.PEER_EVENT_OPEN ,callback:{_ in
            callback.onNext(.peer.identify)
            callback.onCompleted()
        })
        self.peer!.on(.PEER_EVENT_CONNECTION , callback:onRemoteConnect)
        
        return callback
        
    }
    
    func onRemoteConnect(_ e:Any) {
        guard let e = e as? SKWDataConnection else{
            return
        }
        
        let label = e.metadata!
        
        e.send("open" as NSObject)
        
        e.on(.DATACONNECTION_EVENT_DATA, callback: {obj in
            
            let labels = label.components(separatedBy: "/")
            guard labels.count == 4 else{
                return
            }
            let item_id = labels[3]
            
            guard let obj = obj as? NSData else {
                return
            }
            
            let file_manager = FileManager()
            let tmp_file_path = file_manager.temporaryDirectory.appendingPathComponent(item_id)
            
            
            try? obj.write(to: tmp_file_path)
            
            self.controller.onItemReceive(label)
            e.close()
        })
        
    }
    
}



class FirebaseAdapterImpl {
    
    let user_id:String
    let direction:Direction
    let controller:Controller
    let database:Database
    
    init(_ user_id:String , _ direction:Direction, _ controller:Controller) {
        self.user_id = user_id
        self.direction = direction
        self.controller = controller
        
        database = Database.database()
        let ref = database.reference()
        ref.child("/state/" + user_id + "/sent_group_join_request_list").observe(.value, with: {snapshot in
            guard let value = snapshot.value as? [[String:Any]] else {
                self.controller.onSentGroupJoinRequestUpdate([])
                return
            }
            let join_request = value.map({SentGroupJoinRequest(group_id : $0["group_id"] as! String , member_name: $0["member_name"] as! String)})
            
            self.controller.onSentGroupJoinRequestUpdate(join_request)
            
        })
        
        ref.child("/state/" + user_id + "/received_group_join_request_list").observe(.value, with: {snapshot in
            guard let value = snapshot.value as? [String:[[String:String]]] else {
                self.controller.onReceivedGroupJoinRequestUpdate([])
                return
            }
            
            var all_group_received_join_request_list:[ReceivedGroupJoinRequest] = []
            for (group_id , group_received_join_request_list) in value {
                for received_join_request in group_received_join_request_list  {
                    
                    all_group_received_join_request_list += [
                        ReceivedGroupJoinRequest(
                            group_id:group_id,
                            user_id: received_join_request["user_id"]!,
                            member_name: received_join_request["member_name"]!
                        )]
                }
            }
            self.controller.onReceivedGroupJoinRequestUpdate(all_group_received_join_request_list)
        })
        
        ref.child("/state/" + user_id + "/belong_group_list").observe(.value, with: {snapshot in
            guard let value = snapshot.value as? [String] else {
                self.controller.onBelongListUpdate([])
                return
            }
            self.controller.onBelongListUpdate(value)
        })
        
        ref.child("/state/" + user_id + "/item_list").observe(.value, with: {snapshot in
            guard let value = snapshot.value as? [String:[[String:String]]] else {
                return
            }
            
            var all_item_list:[Item] = []
            for (group_id , item_map_list) in value {
                for item_map in item_map_list {
                    let item_id = (item_map["item_id"]!)
                    let item_title = (item_map["item_title"] ) ?? ""
                    let publisher_id = item_map["publisher_id"]!
                    let hash = item_map["hash"]!
                    all_item_list += [
                        Item(group_id:group_id,item_id:item_id,item_title:item_title,publisher_id:publisher_id,hash:hash)
                    ]
                }
                
            }
            self.controller.onItemListUpdate(all_item_list)
            
        })
        
        ref.child("/state/" + user_id + "/member_list").observe(.value, with: {snapshot in
            guard let value = snapshot.value as? [String:[[String:String]]] else {
                return
            }
            
            var all_member_list:[Member] = []
            for (group_id , group_member_map_list) in value {
                for  member_map in group_member_map_list {
                    all_member_list += [Member(group_id:group_id,
                                                  user_id:member_map["user_id"]!,
                                                  member_name:member_map["member_name"]!)]
                }
            }
            self.controller.onMemberUpdate(all_member_list)
            
        })
        
        ref.child("/entities/groups").observe(.value, with: {snapshot in
            
            guard let value = snapshot.value as? [[String:String]] else {
                return
            }
            
            var all_group_list:[Group] = []
            for  group_map in value {
                all_group_list += [Group(group_id: group_map["group_id"]!,group_name:group_map["group_name"]!)]
                
            }
            
            self.controller.onGroupListUpdate(all_group_list)
            
        })
        
        ref.child("/notifications/" + user_id).removeValue()
        ref.child("/notifications/" + user_id).observe(.childAdded, with: {snapshot in
            
            guard let value = snapshot.value as? [String:Any] else {
                return
            }
            guard let type = value["type"] as? String else {
                
                return
            }
            
            guard let payload = value["payload"] as? [String:Any] else {
                return
            }
            
            switch type {
            case "on_other_device_login" :
                let group_id = payload["group_id"]! as! String
                let device_id = payload["device_id"]! as! String
                controller.onOtherDeviceLogin(group_id, device_id)
                return
                
            case "on_group_create":
                let group_id = payload["group_id"]! as! String
                let device_id = payload["device_id"]! as! String
                self.controller.onGroupCreate(group_id,device_id)
                return
                
            case "item_request":
                let group_id = payload["group_id"]! as! String
                let item_id_list = payload["item_id_list"]! as! [String]
                let give_device_id = payload["give_device_id"]! as! String
                let take_device_id = payload["take_device_id"]! as! String
                let take_peer_id = payload["take_peer_id"]! as! String
                self.controller.onItemRequest(group_id, take_device_id, take_peer_id, give_device_id, item_id_list)
                return
                
            case "item_request_for_all":
                let group_id = payload["group_id"]! as! String
                let item_id_list = payload["item_id_list"]! as! [String]
                let take_device_id = payload["take_device_id"]! as! String
                let take_peer_id = payload["take_peer_id"]! as! String
                self.controller.onItemRequestForAll(group_id, take_device_id, take_peer_id, item_id_list)
                return
                
            default:
                return
            }
            
            
        })
        
        let _ = direction.send_item_request.subscribe(onNext: { self.sendItemRequest($0) })
        let _ = direction.send_item_request_for_all.subscribe(onNext: {self.sendItemRequestForAll($0)})
        let _ = direction.send_login.subscribe(onNext: { self.sendLogin($0) })
        let _ = direction.send_group_join_request.subscribe(onNext: {self.sendJoinRequest($0.group_id, $0.member_name) })
        let _ = direction.send_accept_group_join_request.subscribe(onNext: { self.sendAcceptJoinRequest($0.group_id, $0.user_id) })
        let _ = direction.send_reject_group_join_request.subscribe(onNext: { self.sendRejectJoinRequest($0.group_id, $0.user_id) })
        let _ = direction.send_create_group.subscribe(onNext: { self.sendCreateGroup($0.group_name, $0.member_name, $0.device_id) })
        let _ = direction.send_delete_item.subscribe(onNext: { self.sendDeleteitem($0.group_id, $0.item_id)})
        
    }
    func sendItemRequest(_ item_request: ItemRequest) {
        
        let payload = [
            "group_id" : item_request.group_id ,
            "item_id_list" : item_request.item_id_list ,
            "take_device_id" : item_request.take_device_id ,
            "take_peer_id" : item_request.take_peer_id ,
            "give_device_id" : item_request.give_device_id
            ] as [String : Any]
        self.database
            .reference()
            .child("write/" + self.user_id)
            .childByAutoId()
            .setValue(["type" : "item_request", "payload" : payload ])
        
    }
    func sendItemRequestForAll(_ item_request: ItemRequestForAll) {
        let payload = [
            "group_id" : item_request.group_id ,
            "item_id_list" : item_request.item_id_list ,
            "take_device_id" : item_request.take_device_id ,
            "take_peer_id" : item_request.take_peer_id ,
            ] as [String : Any]
        self.database
            .reference()
            .child("write/" + self.user_id)
            .childByAutoId()
            .setValue(["type" : "item_request_for_all", "payload" : payload ])
        
    }
    func sendLogin(_ device_id: String) {
        let payload = ["device_id" : device_id]
        self.database
            .reference()
            .child("write/" + self.user_id)
            .childByAutoId()
            .setValue(["type" : "on_device_login", "payload" : payload])
    }
    func sendJoinRequest(_ group_id: String,_ member_name:String) {
        let payload = ["group_id" : group_id , "member_name" : member_name]
        self.database.reference().child("write/" + self.user_id).childByAutoId().setValue(["type" : "group_group_join_request", "payload" : payload ])
        
    }
    func sendAcceptJoinRequest(_ group_id:String,_ user_id:String){
        let payload = ["group_id" : group_id , "user_id" : user_id]
        self.database.reference().child("write/" + self.user_id).childByAutoId().setValue(["type" : "accept_group_join_request", "payload" : payload ])
    }
    func sendRejectJoinRequest(_ group_id:String,_ user_id:String){
        let payload = ["group_id" : group_id , "user_id" : user_id]
        self.database.reference().child("write/" + self.user_id).childByAutoId().setValue(["type" : "reject_group_join_request", "payload" : payload ])
    }
    func sendCreateGroup(_ group_name:String,_ member_name:String,_ device_id:String){
        let payload = ["group_name" : group_name , "member_name" : member_name,"device_id":device_id]
        self.database.reference().child("write/" + self.user_id).childByAutoId().setValue(["type" : "create_group", "payload" : payload ])
        
    }
    func sendAdditem(_ group_id:String,_ item_id:String){
        let payload = ["group_id" : group_id , "item_id" : item_id ]
        self.database.reference().child("write/" + self.user_id).childByAutoId().setValue(["type" : "add_item", "payload" : payload])
    }
    func sendDeleteitem(_ group_id:String ,_ item_id:String){
        let payload = ["group_id" : group_id , "item_id" : item_id ]
        self.database.reference().child("write/" + self.user_id).childByAutoId().setValue(["type" : "delete_item", "payload" : payload])
    }
}
