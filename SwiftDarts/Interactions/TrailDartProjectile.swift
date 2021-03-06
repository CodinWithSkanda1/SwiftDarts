//
//  TrailDartProjectile.swift
//  SwiftDarts
//
//  Created by Wilson on 4/9/19.
//  Copyright © 2019 Wilson. All rights reserved.
//

import Foundation
import SceneKit

extension float4 {
    init(color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        self.init(Float(red), Float(green), Float(blue), Float(alpha))
    }
}

extension SCNGeometrySource {
    convenience init(vertices: [float3]) {
        self.init(vertices: vertices.map(SCNVector3.init))
    }
    convenience init(colors: [float4]) {
        
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        self.init(data: colorData,
                  semantic: .color,
                  vectorCount: colors.count,
                  usesFloatComponents: true,
                  componentsPerVector: 4,
                  bytesPerComponent: MemoryLayout.size(ofValue: colors[0].x),
                  dataOffset: 0,
                  dataStride: MemoryLayout.stride(ofValue: colors[0]))
    }
    
}

extension Array {
    mutating func removeAllButLast(_ countToKeep: Index) {
        let countToRemove = Swift.max(count - countToKeep, 0)
        removeFirst(countToRemove)
    }
}

class TrailDartProjectile: Projectile {
    var accurateCollisionTrigger: SCNNode?
    var helperCollisionTrigger: SCNNode?
    
    var dartTail: SCNNode?
    
    override var team: Team {
        didSet {
            dartTail?.geometry?.firstMaterial?.diffuse.contents = team.color
            
            if let levelsOfDetail = dartTail?.geometry?.levelsOfDetail {
                for lod in levelsOfDetail {
                    lod.geometry?.firstMaterial?.diffuse.contents = team.color
                }
            }
        }
    }
    
    var didHit = false
    
    // default values the result of a vast user study.
    static let dartSize: Float = 2
    static let defaultTrailWidth: Float = 0.2 // Default trail with with ball size as the unit (1.0 represents same width as the ball)
    static let defaultTrailLength: Int = 40
    
    let trailNode = SCNNode()
    let trailMat = SCNMaterial()
    let epsilon: Float = 1.19209290E-07 // upper limit on float rounding error
    
    var worldPositions: [float3] = []
    
    var trailHalfWidth: Float {
        return (UserDefaults.standard.trailWidth ?? TrailDartProjectile.defaultTrailWidth) * TrailDartProjectile.dartSize * 0.5
    }
    var maxTrailPositions: Int { return UserDefaults.standard.trailLength ?? TrailDartProjectile.defaultTrailLength }
    var trailShouldNarrow: Bool { return UserDefaults.standard.tailShouldNarrow }
    
    override init(prototypeNode: SCNNode, index: Int?, gamedefs: [String : Any]) {
        super.init(prototypeNode: prototypeNode, index: index, gamedefs: gamedefs)
        
        accurateCollisionTrigger = objectRootNode.childNode(withName: "dart_collision_trigger_accurate", recursively: true)
        helperCollisionTrigger = objectRootNode.childNode(withName: "dart_collision_trigger_helper", recursively: true)
        
        guard let dartTeamTail = objectRootNode.childNode(withName: "dart_team_base", recursively: true) else {
            fatalError("Projectile node has no tail")
        }
        dartTail = dartTeamTail
        
        guard let accurateTriggerPhysicsBody = accurateCollisionTrigger?.physicsBody else {
            fatalError("Projectile node has no collision trigger")
        }
        
        guard let helperTriggerPhysicsBody = helperCollisionTrigger?.physicsBody else {
            fatalError("Projectile node has no collision trigger")
        }
        
        accurateTriggerPhysicsBody.contactTestBitMask = CollisionMask([.board, .triggerVolume]).rawValue
        accurateTriggerPhysicsBody.categoryBitMask = CollisionMask([.projectile]).rawValue
        
        helperTriggerPhysicsBody.contactTestBitMask = CollisionMask([.board, .triggerVolume]).rawValue
        helperTriggerPhysicsBody.categoryBitMask = CollisionMask([.projectile]).rawValue
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func launch(velocity: GameVelocity, lifeTime: TimeInterval, delegate: ProjectileDelegate) {
        super.launch(velocity: velocity, lifeTime: lifeTime, delegate: delegate)
        
        addTrail()
    }
    
    override func onSpawn() {
        super.onSpawn()
        addTrail()
    }
    
    override func disable() {
        super.disable()
        removeTrail()
    }
    
    override func despawn() {
        super.despawn()
        removeTrail()
    }
    
    private func addTrail() {
        guard let _ = physicsNode else { return }
        trailNode.castsShadow = false
        
        guard let delegate = delegate else { return }
        delegate.addNodeToLevel(node: trailNode)
    }
    
    private func removeTrail() {
        trailNode.removeFromParentNode()
    }
    
    private var tempWorldPositions = [float3]()
    private var colors = [float4]()
    
    override func onDidApplyConstraints(renderer: SCNSceneRenderer) {
        let frameSkips = 3
        guard (GameTime.frameCount + index) % frameSkips == 0 else { return }
        guard let physicsNode = physicsNode else { return }
        
        if worldPositions.count > (maxTrailPositions / frameSkips) {
            removeVerticesPair()
        }
        
        let pos = physicsNode.presentation.simdWorldPosition
        
        var trailDir: float3
        if let prevPos = worldPositions.last {
            trailDir = pos - prevPos
            
            let lengthSquared = length_squared(trailDir)
            if lengthSquared < epsilon {
                removeVerticesPair()
                updateColors()
                let localPositions = tempWorldPositions.map { trailNode.presentation.simdConvertPosition($0, from: nil) }
                trailNode.presentation.geometry = createTrailMesh(positions: localPositions, colors: colors)
                return
            }
            trailDir = normalize(trailDir)
        } else {
            trailDir = objectRootNode.simdWorldFront
        }
        
        var right = cross(float3(0.0, 1.0, 0.0), trailDir)
        right = normalize(right)
        let scale: Float = 1.0 //Float(i - 1) / worldPositions.count
        var halfWidth = trailHalfWidth
        if trailShouldNarrow {
            halfWidth *= scale
        }
        let u = pos + right * halfWidth
        let v = pos - right * halfWidth
        
        worldPositions.append(pos)
        tempWorldPositions.append(u)
        tempWorldPositions.append(v)
        
        colors.append(float4())
        colors.append(float4())
        
        updateColors()
        let localPositions = tempWorldPositions.map { trailNode.presentation.simdConvertPosition($0, from: nil) }
        trailNode.presentation.geometry = createTrailMesh(positions: localPositions, colors: colors)
    }
    
    private func removeVerticesPair() {
        worldPositions.removeFirst()
        tempWorldPositions.removeFirst(2)
        colors.removeFirst(2)
    }
    
    private func updateColors() {
        let baseColor = float4(color: team.color)
        for i in 0..<colors.count {
            let scale = Float(i) / Float(colors.count)
            colors[i] = baseColor * scale
        }
    }
    
    func createTrailMesh(positions: [float3], colors: [float4]) -> SCNGeometry? {
        guard positions.count >= 4 else { return nil }
        let posSource = SCNGeometrySource(vertices: positions)
        let colorSource = SCNGeometrySource(colors: colors)
        
        let element = SCNGeometryElement(indices: Array(0..<UInt16(positions.count)), primitiveType: .triangleStrip)
        
        let trailMesh = SCNGeometry(sources: [posSource, colorSource], elements: [element])
        guard let material = trailMesh.firstMaterial else { fatalError("created geometry without material") }
        material.isDoubleSided = true
        material.lightingModel = .constant
        material.blendMode = .add
        material.writesToDepthBuffer = false
        
        return trailMesh
    }

}
