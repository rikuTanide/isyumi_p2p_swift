
import Foundation
import RxSwift

//キャンセラ
typealias OnConnect = (_ peer_id:String) -> Void

// 構造体

// ここからモデル層で使う構造体
struct Group {
    var group_id: String
    var group_name: String
}

struct Item {
    var group_id:String
    var item_id:String
    var item_title:String
    var publisher_id:String
    var hash: String
}

struct Member {
    var group_id:String
    var user_id:String
    var member_name:String
}

// 自分が他のグループに入りたいと言った申請
struct SentGroupJoinRequest {
    var group_id:String
    var member_name:String
}

// 他のユーザーが自分が所属しているグループに入りたいと言ってきた申請
struct ReceivedGroupJoinRequest {
    var group_id:String
    var user_id:String
    var member_name:String
}

// ファイルがiPhoneのストレージ内に存在するか
struct ItemFile {
    var group_id:String
    var item_id:String
}

// ある特定の端末にファイルを要求するエンティティ
struct ItemRequest {
    var group_id:String
    var item_id_list:[String]
    var take_device_id:String
    var take_peer_id:String
    var give_device_id:String
}

// このアイテム持ってたらちょうだいとグループの全員に送った
struct ItemRequestForAll {
    var group_id:String
    var item_id_list:[String]
    var take_device_id:String
    var take_peer_id:String
    
}

struct CreateGroup {
    var group_name:String
    var member_name:String
    var device_id:String
}

// ここからViewで使う構造体
struct SelectableGroup {
    var group_id:String
    var group_name:String
    var member_name:String
    var requesting: Bool
    
}

struct ItemView {
    var group_id:String
    var item_id:String
    var item_title:String
    var publisher_name:String
    var exists:Bool
}

struct RequestableGroup {
    var group_id:String
    var group_name:String
    var member_name:String
    var requesting:Bool
}

// ここからWorkerが使う構造体
struct ItemSend {
    var group_id:String
    var item_id:String
    var take_device_id:String
    var take_peer_id:String
    var give_device_id:String
}


// StateとViewへのStream
class Model {
    
    var group_list:[Group] = []
    var sent_group_join_request_list:[SentGroupJoinRequest] = []
    var received_group_join_request_list:[ReceivedGroupJoinRequest] = []
    var belong_group_list:[String] = [] // 今現在入っているグループ一覧
    var current_group_id:String? // 現在Viewでどのグループを表示しているか
    var member_list:[Member] = [] // 自分が所属しているグループに所属しているメンバー全員
    var item_list:[Item] = []
    var file_list:[ItemFile] = []
    
    var peer_id:String?
    
    // 参加しているグループ一覧を配信するObservable
    // 申請中も含まれる
    var selectable_group_observable = Variable<[SelectableGroup]>([])
    
    // 現在どのグループに参加申請可能かを配信するObservable
    // 申請中も含まれる
    var requestable_group_list_observable = Variable<[RequestableGroup]>([])
    
    var item_list_observable = Variable<[ItemView]>([])
    var received_join_request_list_observable = Variable<[ReceivedGroupJoinRequest]>([])
    var member_list_observable = Variable<[Member]>([])
    
    var user_id:String
    
    init(_ user_id:String) {
        self.user_id = user_id
    }
    
    
    // 参加済グループのリスト
    // UI上の理由で参加申請中のグループも混ぜる
    private func addSelectableGroupList() {
        

        
        func belongOrRequesting(_ group:Group) -> Bool {
            return
                self.belong_group_list.index(of: group.group_id) != nil ||
                    self.sent_group_join_request_list.contains(where: {$0.group_id == group.group_id})
        }
        
        
        func toSelectableGroup(_ group:Group)-> SelectableGroup {
            
            
            if let sent_group_join_request = self.sent_group_join_request_list.first(where:{$0.group_id == group.group_id}) {
                return SelectableGroup(group_id: group.group_id, group_name: group.group_name, member_name: sent_group_join_request.member_name, requesting: true)
            }
            
            let member = self.member_list.first(where:{$0.group_id == group.group_id && $0.user_id == self.user_id})
            return SelectableGroup(group_id: group.group_id, group_name: group.group_name, member_name: member?.member_name ?? "", requesting: false)
            
            
        }
        
        let selectable_group_list = group_list
            .filter(belongOrRequesting)
            .map(toSelectableGroup)
        
        self.selectable_group_observable.value = selectable_group_list
    }

    
    // 参加申請可能なグループのリスト
    // UI上の理由で参加申請中のグループも混ぜる
    private func addRequestableGroupList() {

        func notBelong(_ group:Group) -> Bool {
            return belong_group_list.index(of:group.group_id) == nil
        }
        
        func toRequestableGroup(_ group:Group) -> RequestableGroup {
            let sent_group_join_request = self.sent_group_join_request_list.first(where:{$0.group_id == group.group_id})
            return RequestableGroup(
                group_id:group.group_id,
                group_name:group.group_name,
                member_name: sent_group_join_request?.member_name ?? "",
                requesting: sent_group_join_request != nil
            )
        }
        
        let requestable_list = self.group_list.filter(notBelong).map(toRequestableGroup)
        requestable_group_list_observable.value = requestable_list
        
    }
    

    

    private func addItemList() {
        
        guard let group_id = self.current_group_id else {
            item_list_observable.value = []
            return
        }
        
        func fileExists(_ item_id:String) -> Bool {
            
            let file = self.file_list.first(where: {$0.group_id == group_id && $0.item_id == item_id})
            return file != nil
        }
        
        func mapItemView(_ item:Item) ->ItemView {
            let publisher = member_list.first(where: {$0.group_id == group_id && $0.user_id == item.publisher_id})
            let publisher_name = publisher?.member_name ?? ""
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy/MM/DD HH:mm"
            let exists = fileExists(item.item_id)
            return ItemView(
                group_id: group_id,
                item_id: item.item_id,
                item_title: item.item_title,
                publisher_name: publisher_name,
                exists: exists)
        }
        
        let item_view_list = self.item_list
            .filter({$0.group_id == group_id})
            .map(mapItemView)
        item_list_observable.value = item_view_list
        
    }
    

    
    private func addReceivedGroupJoinRequestList() {
        
        guard let group_id = current_group_id else {
            received_join_request_list_observable.value = []
            return
        }
        
        received_join_request_list_observable.value = self.received_group_join_request_list.filter({$0.group_id == group_id})
        
    }
    
    private func addMemberList() {
        
        guard let group_id = current_group_id else {
            self.member_list_observable.value = []
            return
        }
        member_list_observable.value = self.member_list.filter({$0.group_id == group_id})
    }
    
    func update() {
        addSelectableGroupList()
        addRequestableGroupList()
        addItemList()
        addReceivedGroupJoinRequestList()
        addMemberList()
    }
    
}


// Direction

class Direction {
    
    let write = PublishSubject<ItemFile>() //writeというのはtmp領域からグループごとのファイルに移すことを言う
    let item_send = PublishSubject<ItemSend>()
    let group_select = PublishSubject<String>()
    let send_item_request = PublishSubject<ItemRequest>()
    let send_item_request_for_all = PublishSubject<ItemRequestForAll>()
    let send_login = PublishSubject<String>() // device_idを送る
    let send_group_join_request = PublishSubject<SentGroupJoinRequest>()
    let send_accept_group_join_request = PublishSubject<(group_id:String,user_id:String)>()
    let send_reject_group_join_request = PublishSubject<(group_id:String,user_id:String)>()
    let send_create_group = PublishSubject<CreateGroup>()
    let send_add_item = PublishSubject<Item>()
    let send_delete_item = PublishSubject<(group_id:String,item_id:String)>()
    
}

// Viewerが使う構造体



// answerer

protocol LocalItemListUpper {
    func listup() -> [ItemFile]
}

protocol DeviceIDRegistry {
    func read()->String
}

protocol RandomString {
    func generate(_ length:Int) -> String
}

protocol CurrentGroupRegistry {
    func save(_ group_id:String)
    func read() -> String?
}

// Reporter
protocol P2P {
    
    func onReceive()-> Variable<ItemFile>
    func connect() -> Variable<String>
}
