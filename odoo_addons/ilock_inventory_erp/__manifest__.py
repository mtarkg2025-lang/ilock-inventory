{
    'name': 'I LOCK Industrial Inventory Control',
    'summary': 'Industrial inventory controls integrated with Odoo Inventory',
    'version': '19.0.1.0.0',
    'category': 'Inventory/Inventory',
    'author': 'I LOCK',
    'license': 'LGPL-3',
    'depends': ['stock', 'product'],
    'data': [
        'security/ilock_inventory_security.xml',
        'security/ir.model.access.csv',
        'views/product_template_views.xml',
        'views/stock_picking_views.xml',
        'views/ilock_inventory_count_views.xml',
        'views/ilock_inventory_menus.xml',
    ],
    'installable': True,
    'application': False,
}
