import Foundation

// Controller
class Controller {

    let model:Model
    let direction:Direction
    let local_item_listupper:LocalItemListUpper
    let device_id_registry:DeviceIDRegistry
    let random_string: RandomString
    let current_group_registry:CurrentGroupRegistry
    let p2p:P2P
    let firebase:Firebase
    
    init(
        model:Model,
        direction:Direction,
        local_item_listupper:LocalItemListUpper,
        device_id_registry:DeviceIDRegistry,
        random_string:RandomString,
        current_group_registry:CurrentGroupRegistry,
        p2p:P2P,
        firebase:Firebase){
        self.model = model
        self.direction = direction
        self.local_item_listupper = local_item_listupper
        self.device_id_registry = device_id_registry
        self.random_string = random_string
        self.current_group_registry = current_group_registry
        self.p2p = p2p
        self.firebase = firebase
    }
    
    
    
    func onOtherDeviceLogin(_ group_id:String,_ other_device_id:String){
        // 他の端末がログインしたらそのグループのアイテム一覧を取得し
        // ローカルにあるものは除いて
        // そのデバイスにリクエストする
        
        let local_item_list = self.local_item_listupper.listup()
        let this_device_id = self.device_id_registry.read()
        
        
        func existsFile(_ item_id:String) -> Bool {
            for file in local_item_list {
                if file.group_id == group_id && file.item_id == item_id {
                    return true
                }
            }
            return false
        }
        
    
        // まだSkyWayにログインできてなかったら無視
        guard let this_peer_id = self.model.peer_id else{
            return
        }
        
        // ログインしたのが自分だったら無視
        guard this_device_id != other_device_id else {
            return
        }
        
        let item_id_list = self.model
            .item_list
            .filter({$0.group_id == group_id})
            .filter({existsFile($0.group_id)})
            .map({$0.group_id})
        
        // そのグループの相手もを全部持ってたら終了
        if item_id_list.count == 0 {
            return
        }
        
        let request_list = ItemRequest(
            group_id:group_id,
            item_id_list:item_id_list,
            take_device_id:this_device_id,
            take_peer_id:this_peer_id,
            give_device_id:other_device_id)
        
        self.direction.send_item_request.onNext(request_list)
    }
    
    // ここからUIから来るであろうイベント
    func groupSelect(_ group_id:String){
        self.model.current_group_id = group_id
        self.model.update()
        self.direction.group_select.onNext(group_id)
    }
    func groupJoinRequest(_ group_id:String,_ member_name:String){
        // 楽観的UIのために一度データを入れる。Firebaseからデータが帰ってきたらもう一度上書きされる予定
        let new_join_request_list = self.model.sent_group_join_request_list + [SentGroupJoinRequest(group_id:group_id,member_name:member_name)]
        self.model.sent_group_join_request_list = new_join_request_list
        self.model.update()
        
        self.direction.send_group_join_request.onNext(SentGroupJoinRequest(group_id:group_id,member_name:member_name))
    }
    
    func groupCreate(_ group_name:String,_ member_name:String){
        // FirebaseからOnCreateGroupイベントを返してもらうために自分のdevice_idも一緒に送る
        let device_id = self.device_id_registry.read()
        self.direction.send_create_group.onNext(CreateGroup(group_name:group_name,member_name:member_name,device_id:device_id))
    }

    func addItem(_ item_id:String) {
        guard let group_id = self.model.current_group_id else {
            return
        }
        self.direction.write.onNext(ItemFile(group_id: group_id, item_id: item_id))
        let user_id = self.model.user_id
        let item = Item(group_id: group_id, item_id: item_id, item_title: "", publisher_id: user_id, hash: "")
        self.direction.send_add_item.onNext(item)
        
        
        self.model.file_list = self.local_item_listupper.listup()
        self.model.item_list = self.model.item_list + [item]
        self.model.update()
        
    }
    
    
    func accesptGroupJoinRequest(_ group_id:String, _ user_id:String){
        // 許諾したので受け取った参加申請を削除
        let new_list = self.model.received_group_join_request_list
            .filter({!($0.group_id == group_id && $0.user_id == user_id)})
        self.model.received_group_join_request_list = new_list
        self.model.update()
        
        self.direction.send_accept_group_join_request.onNext(group_id: group_id,user_id:user_id)

    }
    
    func rejectGroupJoinRequest(_ group_id:String, _ user_id:String){
        let new_list = self.model.received_group_join_request_list
            .filter({!($0.group_id == group_id && $0.user_id == user_id)})
        self.model.received_group_join_request_list = new_list
        self.model.update()
        
        self.direction.send_reject_group_join_request.onNext(group_id: group_id,user_id:user_id)
    }

    // ここからFirebaseからのイベント
    func onGroupListUpdate(_ group_list:[Group]){
        self.model.group_list = group_list
        self.model.update()
    }
    
    var first_update = true
    func onItemListUpdate(_ item_list:[Item]){
        
        let local_list = self.local_item_listupper.listup()
        let this_device_id = self.device_id_registry.read()
        
        func existsFile(_ item:Item) -> Bool{
            for file in local_list {
                if item.group_id == file.group_id && item.item_id == file.item_id {
                    return true
                }
            }
            return false
        }
        
        func sendRequestList(_ peer_id:String) {
            
            for group_id in self.model.belong_group_list {
                let item_id_list = item_list
                    .filter({$0.group_id == group_id})
                    .filter({!existsFile($0)})
                    .map({$0.item_id})
                
                guard item_id_list.count > 0 else {
                    return
                }
                
                let item_request_for_all = ItemRequestForAll(
                    group_id:group_id,
                    item_id_list : item_id_list,
                    take_device_id:this_device_id,
                    take_peer_id:peer_id)
                self.direction.send_item_request_for_all.onNext(item_request_for_all)
            }
            
            
        }
        
        self.model.item_list = item_list
        model.update()
        
        if !first_update {
            guard let peer_id = self.model.peer_id else {
                return
            }
            
            sendRequestList(peer_id)
            return
        }
        first_update = false
        
        // 最初の曲取得なら
        // キャッシュをアップデートし
        // p2pを接続
        // 繋がったらリクエストを送って
        // ログインを通知する
        
        
        
        func onConnect(_ peer_id:String) {
            self.model.peer_id = peer_id
            sendRequestList(peer_id)
        }
        let _ = self.p2p.connect().asObservable().subscribe(onNext: {onConnect($0)})
    }
    
    func onMemberUpdate(_ member_list:[Member]){
        self.model.member_list = member_list
        self.model.update()
        
    }
    
    func onBelongListUpdate(_ belong_list:[String]){
        self.model.belong_group_list = belong_list
        self.model.update()
        
    }
    
    func onSentGroupJoinRequestUpdate(_ sent_join_request_list:[SentGroupJoinRequest]){
        self.model.sent_group_join_request_list = sent_join_request_list
        self.model.update()
        
    }
    
    func onReceivedGroupJoinRequestUpdate(_ receive_join_request_list:[ReceivedGroupJoinRequest]){
        self.model.received_group_join_request_list = receive_join_request_list
        self.model.update()
        
    }
    func onItemRequest(_ group_id:String,_ take_device_id:String,_ take_peer_id:String,_ give_device_id:String,_ item_id_list:[String]) {
        
        guard let _ = self.model.peer_id else {
            return
        }
        guard give_device_id == self.device_id_registry.read() else {
            return
        }
        guard take_device_id != self.device_id_registry.read() else {
            return
        }
        
        let list = self.local_item_listupper.listup()
        func inRequestList(_ file:ItemFile) ->Bool {
            return file.group_id == group_id && item_id_list.contains(file.item_id)
        }
        for file in list.filter(inRequestList) {
            let item_send = ItemSend(group_id:group_id,item_id:file.item_id,take_device_id:take_device_id,take_peer_id: take_peer_id,give_device_id: give_device_id)
            self.direction.item_send.onNext(item_send)
        }
    }
    func onItemRequestForAll(_ group_id:String,_ take_device_id:String,_ take_peer_id:String,_ item_id_list:[String]) {
        guard let _ = self.model.peer_id else {
            return
        }
        let this_device_id = self.device_id_registry.read()
        //　修正した
        guard this_device_id != take_device_id else {
            return
        }
        let list = self.local_item_listupper.listup()
        func inRequestList(_ file:ItemFile) ->Bool {
            return file.group_id == group_id && item_id_list.contains(file.item_id)
        }
        for file in list.filter(inRequestList) {
            let item_send = ItemSend(group_id:group_id,item_id:file.item_id,take_device_id:take_device_id,take_peer_id: take_peer_id,give_device_id: this_device_id)
            self.direction.item_send.onNext(item_send)
        }
    }
    
    // WebRTCからデータが来た
    func onItemReceive(_ label:String){
        let labels = label.components(separatedBy: "/")
        guard labels.count == 4 else{
            return
        }
        let group_id = labels[0]
        //        let _ = labels[1]
        //        let _ = labels[2]
        let item_id = labels[3]
        self.direction.write.onNext(ItemFile(group_id: group_id, item_id: item_id))
        
        
        self.model.file_list = self.local_item_listupper.listup()
        self.model.update()
        
    }
    func onGroupCreate(_ group_id:String , _ device_id:String){
        
        if device_id != self.device_id_registry.read() {
            return
        }
        self.model.current_group_id = group_id
        self.current_group_registry.save(group_id)
    }
}
