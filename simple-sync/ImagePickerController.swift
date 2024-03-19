//
//  ImagePickerController.swift
//  simple-sync
//
//  Created by Wayne Carter on 3/16/24.
//

import UIKit

class ImagePickerController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    var collectionView: UICollectionView!
    let closeButton = UIButton(type: UIButton.ButtonType.close)
    let images = ["bell-pepper", "carrots", "cherries", "blueberries", "chocolate-chip-cookies", "doughnut"]
    var imageSelected: ((_ image: UIImage) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    private func setup() {
        view.backgroundColor = .systemBackground
        
        // Set up close button
        closeButton.configuration?.buttonSize = .large
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        
        // Set up images collection view
        let collectionViewLayout = {
            // Define the size and spacing
            let fractionalSize = NSCollectionLayoutDimension.fractionalWidth(0.5)
            let spacing = 5.0
            
            // Define the size of each item
            let itemSize = NSCollectionLayoutSize(widthDimension: fractionalSize, heightDimension: fractionalSize)
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: spacing)
            
            // Create a group to encompass two items horizontally
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: fractionalSize)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            
            // Create the section
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: spacing, bottom: spacing, trailing: 0)
            
            return UICollectionViewCompositionalLayout(section: section)
        }()

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(ImageCollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        view.addSubview(collectionView)
        
        // Set up the layout constraints
        NSLayoutConstraint.activate([
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 15),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -15),
            
            // Collection view
            collectionView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 15),
            collectionView.leftAnchor.constraint(equalTo: view.leftAnchor),
            collectionView.rightAnchor.constraint(equalTo: view.rightAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    @objc func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - UICollectionViewDataSource
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return images.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ImageCollectionViewCell
        cell.imageView.image = UIImage(named: images[indexPath.row])
        
        return cell
    }
    
    // MARK: - UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) {
            cell.contentView.alpha = 0.7
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) {
            cell.contentView.alpha = 1.0
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let imageName = images[indexPath.row]
        if let image = UIImage(named: imageName) {
            imageSelected?(image)
            dismiss(animated: true)
        }
    }
    
    private class ImageCollectionViewCell: UICollectionViewCell {
        let imageView = UIImageView(frame: .zero)
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            backgroundColor = .black
            
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(imageView)
            
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                imageView.rightAnchor.constraint(equalTo: contentView.rightAnchor)
            ])
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }
    }
}
