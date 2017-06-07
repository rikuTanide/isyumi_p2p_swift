//
//  usage.swift
//  isyumi_p2p_swift
//
//  Created by 谷出陸 on 2017/06/07.
//  Copyright © 2017年 riku tanide. All rights reserved.
//

import Foundation

// ここに到達する前にfirebaseのログインが済んでいてユーザーIDが取得できている前提

func main (firebase_user_id:String) {
    
    
    
    let direction = Direction()
    let model = Model(firebase_user_id)
    
    let local_item_listupper = LocalItemListUpperImpl()
    let device_id_registry = DeviceIDRegistryImpl()
    let random_string = RandomStringImpl()
    let current_group_registry = CurrentGroupRegistoryImpl()
    let writer = WriterImpl(direction)
    let p2p = P2PImpl(direction)
    let firebase_adapter = FirebaseAdapterImpl(firebase_user_id,direction)
    
    let controller = Controller(
        model: model,
        direction: direction,
        local_item_listupper: local_item_listupper,
        device_id_registry: device_id_registry,
        random_string: random_string,
        current_group_registry: current_group_registry,
        p2p: p2p)
    
    p2p.controller = controller
    firebase_adapter.controller = controller
    
    // model.item_list_observable.asObservable().subscribe -> ViewControllerへ
    
}
